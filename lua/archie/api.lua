local Job = require("plenary.job")

local M = {}

local defaults = {
  codex_cmd = "codex",
  model = "gpt-5",
  codex_args = {},
  disable_features = { "shell", "sandbox", "mcp", "git", "web_search" },
  cwd = nil,
}

local config = vim.deepcopy(defaults)

local function trim(text)
  return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function extract_text_from_chunks(chunks)
  if type(chunks) ~= "table" then return nil end
  local pieces = {}
  for _, chunk in ipairs(chunks) do
    if type(chunk) == "string" and chunk ~= "" then
      table.insert(pieces, chunk)
    elseif type(chunk) == "table" and type(chunk.text) == "string" and chunk.text ~= "" then
      table.insert(pieces, chunk.text)
    end
  end
  if #pieces > 0 then return table.concat(pieces, "") end
  return nil
end

local function extract_text_from_message(msg)
  if type(msg) ~= "table" then return nil end
  if type(msg.text) == "string" and msg.text ~= "" then return msg.text end
  if type(msg.content) == "string" and msg.content ~= "" then return msg.content end
  if type(msg.content) == "table" then
    return extract_text_from_chunks(msg.content)
  end
  if type(msg.message) == "table" then
    return extract_text_from_message(msg.message)
  end
  return nil
end

local function clean_completion(body)
  if not body or body == "" then return nil end
  body = body:gsub("```%w*\n?", ""):gsub("\n```", ""):gsub("\r", "")
  body = trim(body)
  return body ~= "" and body or nil
end

local function build_inline_prompt(ctx, extra)
  local lines = {}
  table.insert(lines, ("Language: %s"):format(ctx.filetype ~= "" and ctx.filetype or "plain"))
  if ctx.relative_path or ctx.filepath then
    local path = ctx.relative_path or ctx.filepath
    table.insert(lines, ("File: %s"):format(path))
  end
  if ctx.project_root and ctx.project_root ~= "" then
    table.insert(lines, ("Project root: %s"):format(ctx.project_root))
  end
  table.insert(lines, "Cursor prefix:")
  table.insert(lines, ctx.line_prefix or "")
  table.insert(lines, "")
  table.insert(lines, "Cursor suffix:")
  table.insert(lines, ctx.line_suffix or "")
  table.insert(lines, "")
  table.insert(lines, "Surrounding context (closest lines, newest last):")
  table.insert(lines, table.concat(ctx.code or {}, "\n"))
  if type(ctx.symbol_summary) == "table" and #ctx.symbol_summary > 0 then
    table.insert(lines, "")
    table.insert(lines, "Document symbols:")
    for _, sym in ipairs(ctx.symbol_summary) do
      table.insert(lines, sym)
    end
  end
  if extra and extra ~= "" then
    table.insert(lines, "")
    table.insert(lines, extra)
  end
  table.insert(lines, "")
  table.insert(lines, "Completion:")
  return table.concat(lines, "\n")
end

local function wrap_prompt(prompt)
  local header = {
    "You generate inline completions for Neovim.",
    "Return only the text to insert after the cursor—no explanations, no fencing, no commentary.",
    "",
  }
  return table.concat(header, "\n") .. prompt
end

local function run_codex(prompt, opts)
  opts = opts or {}
  prompt = wrap_prompt(prompt)
  local args = { "exec", "-m", config.model, "--json" }
  local cwd = nil

  if opts.cwd and type(opts.cwd) == "string" and opts.cwd ~= "" then
    cwd = opts.cwd
  elseif type(config.cwd) == "string" and config.cwd ~= "" then
    cwd = config.cwd
  end

  for _, feature in ipairs(config.disable_features or {}) do
    table.insert(args, "--disable")
    table.insert(args, feature)
  end

  if opts.codex_args then
    vim.list_extend(args, opts.codex_args)
  elseif config.codex_args and #config.codex_args > 0 then
    vim.list_extend(args, config.codex_args)
  end
  table.insert(args, "-")

  local state = {
    delivered = false,
    partial = {},
  }

  local schedule_result = opts.on_result and vim.schedule_wrap(opts.on_result)
  local schedule_error = opts.on_error and vim.schedule_wrap(opts.on_error)

  local function emit_result(text)
    if state.delivered then return end
    local cleaned = clean_completion(text)
    if not cleaned or cleaned == "" then return end
    state.delivered = true
    if schedule_result then schedule_result(cleaned) end
  end

  local function append_partial(chunk)
    if chunk and chunk ~= "" then table.insert(state.partial, chunk) end
  end

  local function flush_partial()
    if #state.partial == 0 then return nil end
    local text = table.concat(state.partial, "")
    state.partial = {}
    return text
  end

  local function parse_event(event)
    if type(event) ~= "table" then return nil end
    local etype = event.type or (event.item and event.item.type)
    if etype == "item.completed" and type(event.item) == "table" then
      local item = event.item
      local item_type = item.type or item.role
      if item_type == "agent_message" or item_type == "assistant_message" or item_type == "message" then
        return extract_text_from_message(item)
      end
    elseif etype == "agent_message" or etype == "assistant_message" or etype == "message" then
      return extract_text_from_message(event)
    elseif etype == "completion" and type(event.delta) == "string" then
      append_partial(event.delta)
      if event.done then return flush_partial() end
    elseif etype == "response.output_text.delta" and type(event.delta) == "string" then
      append_partial(event.delta)
    elseif etype == "response.completed" or etype == "response.stopped" then
      return flush_partial()
    end
    return nil
  end

  local job = Job:new({
    command = config.codex_cmd,
    args = args,
    writer = prompt .. "\n",
    stdout_buffered = false,
    cwd = cwd,
    on_stdout = function(_, data)
      if not data then return end
      if type(data) == "table" then
        for _, line in ipairs(data) do
          if line and line ~= "" then
            local ok, event = pcall(vim.fn.json_decode, line)
            if ok then
              local text = parse_event(event)
              if text then
                emit_result(text)
                break
              end
            end
          end
        end
      elseif type(data) == "string" and data ~= "" then
        local ok, event = pcall(vim.fn.json_decode, data)
        if ok then
          local text = parse_event(event)
          if text then emit_result(text) end
        end
      end
    end,
    on_exit = function(j, code)
      if code ~= 0 then
        if opts.on_error then
          local err = table.concat(j:stderr_result(), "\n")
          if err == "" then err = ("Codex exited with %d"):format(code) end
          schedule_error(err)
        else
          vim.schedule(function()
            local err = table.concat(j:stderr_result(), "\n")
            if err == "" then
              err = ("Codex exited with %d"):format(code)
            end
            vim.notify(("Archie Codex error: %s"):format(err), vim.log.levels.ERROR)
          end)
        end
        return
      end

      if schedule_result and not state.delivered then
        local raw_events = j:result()
        for _, line in ipairs(raw_events) do
          if line ~= "" then
            local ok, event = pcall(vim.fn.json_decode, line)
            if ok then
              local text = parse_event(event)
              if text then
                emit_result(text)
                break
              end
            end
          end
        end
        if not state.delivered then
          local leftover = flush_partial()
          if leftover then emit_result(leftover) end
        end
      end
    end,
  })

  job:start()
  return job
end

function M.setup(opts)
  opts = opts or {}
  local codex_opts = type(opts.codex) == "table" and opts.codex or opts

  if type(codex_opts.codex_cmd) == "string" then config.codex_cmd = codex_opts.codex_cmd end
  if type(codex_opts.cmd) == "string" then config.codex_cmd = codex_opts.cmd end
  if type(codex_opts.model) == "string" then config.model = codex_opts.model end
  if type(codex_opts.codex_args) == "table" then config.codex_args = codex_opts.codex_args end
  if type(codex_opts.args) == "table" then config.codex_args = codex_opts.args end
  if type(codex_opts.disable_features) == "table" then config.disable_features = codex_opts.disable_features end
  if type(codex_opts.cwd) == "string" then config.cwd = codex_opts.cwd end
end

function M.request_inline_completion(ctx, on_result, on_error)
  if not ctx or not ctx.code then return nil end
  local prompt = build_inline_prompt(ctx)
  return run_codex(prompt, {
    cwd = ctx.project_root or ctx.cwd,
    on_result = function(raw)
      local cleaned = clean_completion(raw)
      if cleaned and on_result then
        on_result(cleaned)
      end
    end,
    on_error = on_error,
  })
end

function M.query_async(prompt, callback, on_error, extra_opts)
  extra_opts = extra_opts or {}
  return run_codex(prompt, {
    cwd = extra_opts.cwd,
    on_result = function(raw)
      if callback then
        callback({ text = trim(raw) })
      end
    end,
    on_error = on_error,
  })
end

return M
