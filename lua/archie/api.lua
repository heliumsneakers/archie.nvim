local Job = require("plenary.job")

local M = {}

local defaults = {
  codex_cmd = "codex",
  model = "gpt-5",
  codex_args = {},
  disable_features = { "shell", "sandbox", "mcp", "git", "web_search" },
}

local config = vim.deepcopy(defaults)

local function trim(text)
  return text:gsub("^%s+", ""):gsub("%s+$", "")
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
  table.insert(lines, "Cursor prefix:")
  table.insert(lines, ctx.line_prefix or "")
  table.insert(lines, "")
  table.insert(lines, "Cursor suffix:")
  table.insert(lines, ctx.line_suffix or "")
  table.insert(lines, "")
  table.insert(lines, "Surrounding context (closest lines, newest last):")
  table.insert(lines, table.concat(ctx.code or {}, "\n"))
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
    "You are Codex running in inline-completion mode for a Neovim plugin.",
    "Respond ONLY with the text to insert after the cursor.",
    "Do not explain, do not run commands, do not inspect repositories, and do not add greetings or commentary.",
    "",
  }
  return table.concat(header, "\n") .. prompt
end

local function run_codex(prompt, opts)
  opts = opts or {}
  prompt = wrap_prompt(prompt)
  local args = { "exec", "-m", config.model, "--json" }

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

  local job = Job:new({
    command = config.codex_cmd,
    args = args,
    writer = prompt .. "\n",
    on_exit = function(j, code)
      if code ~= 0 then
        if opts.on_error then
          local err = table.concat(j:stderr_result(), "\n")
          if err == "" then err = ("Codex exited with %d"):format(code) end
          local handler = opts.on_error
          vim.schedule(function()
            handler(err)
          end)
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

      if opts.on_result then
        local raw_events = j:result()
        local final_message = nil

        for _, line in ipairs(raw_events) do
          if line ~= "" then
            local ok, event = pcall(vim.fn.json_decode, line)
            if ok and type(event) == "table" then
              local etype = event.type or (event.item and event.item.type)
              if etype == "agent_message" or etype == "message" then
                local container = event.item or event
                if container and type(container) == "table" then
                  if type(container.text) == "string" then
                    final_message = container.text
                  elseif type(container.content) == "string" then
                    final_message = container.content
                  elseif type(container.message) == "table" then
                    local msg = container.message
                    if type(msg.content) == "table" then
                      local aggregate = {}
                      for _, chunk in ipairs(msg.content) do
                        if type(chunk) == "table" and chunk.text then
                          table.insert(aggregate, chunk.text)
                        end
                      end
                      if #aggregate > 0 then
                        final_message = table.concat(aggregate, "")
                      end
                    elseif type(msg.content) == "string" then
                      final_message = msg.content
                    end
                  end
                end
              elseif etype == "completion" and type(event.delta) == "string" then
                final_message = (final_message or "") .. event.delta
              end
            end
          end
        end

        if final_message and final_message ~= "" then
          vim.schedule(function()
            opts.on_result(final_message)
          end)
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
end

function M.request_inline_completion(ctx, on_result, on_error)
  if not ctx or not ctx.code then return nil end
  local prompt = build_inline_prompt(ctx)
  return run_codex(prompt, {
    on_result = function(raw)
      local cleaned = clean_completion(raw)
      if cleaned and on_result then
        on_result(cleaned)
      end
    end,
    on_error = on_error,
  })
end

function M.query_async(prompt, callback, on_error)
  return run_codex(prompt, {
    on_result = function(raw)
      if callback then
        callback({ text = trim(raw) })
      end
    end,
    on_error = on_error,
  })
end

return M
