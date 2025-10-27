local Job = require("plenary.job")

local M = {}

local defaults = {
  codex_cmd = "codex",
  model = "gpt-5",
  temperature = 0.1,
  max_tokens = 256,
  codex_args = {},
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
  table.insert(lines, "You are Codex providing inline code completions inside Neovim.")
  table.insert(lines, "Model: " .. config.model)
  table.insert(lines, "Respond with only the text that should be inserted after the cursor.")
  table.insert(lines, "Do not repeat text that already exists after the cursor and do not add explanations.")
  table.insert(lines, "")
  table.insert(lines, ("Filetype: %s"):format(ctx.filetype ~= "" and ctx.filetype or "plain"))
  table.insert(lines, "Cursor prefix:")
  table.insert(lines, ctx.line_prefix or "")
  table.insert(lines, "")
  table.insert(lines, "Cursor suffix:")
  table.insert(lines, ctx.line_suffix or "")
  table.insert(lines, "")
  table.insert(lines, "Surrounding context:")
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
    "Do not explain, do not run commands, do not inspect repositories.",
    "",
  }
  return table.concat(header, "\n") .. prompt
end

local function run_codex(prompt, opts)
  opts = opts or {}
  prompt = wrap_prompt(prompt)
  local tmpfile = vim.fn.tempname()
  local args = { "exec", "-m", config.model, "-o", tmpfile }
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
        pcall(os.remove, tmpfile)
        if opts.on_error then
          local err = table.concat(j:stderr_result(), "\n")
          if err == "" then err = ("Codex exited with %d"):format(code) end
          opts.on_error(err)
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

      local ok, lines = pcall(vim.fn.readfile, tmpfile)
      if ok and opts.on_result then
        opts.on_result(table.concat(lines, "\n"))
      elseif not ok then
        if opts.on_error then
          opts.on_error("Failed to read Codex response")
        else
          vim.schedule(function()
            vim.notify("Archie: failed to read Codex response file", vim.log.levels.ERROR)
          end)
        end
      end
      pcall(os.remove, tmpfile)
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
  if type(codex_opts.temperature) == "number" then config.temperature = codex_opts.temperature end
  if type(codex_opts.max_tokens) == "number" then config.max_tokens = codex_opts.max_tokens end
  if type(codex_opts.codex_args) == "table" then config.codex_args = codex_opts.codex_args end
  if type(codex_opts.args) == "table" then config.codex_args = codex_opts.args end
end

function M.request_inline_completion(ctx, on_result, on_error)
  if not ctx or not ctx.code then return nil end
  local prompt = build_inline_prompt(ctx)
  return run_codex(prompt, {
    on_result = function(raw)
      local cleaned = clean_completion(raw)
      if cleaned and on_result then
        on_result(cleaned)
      elseif not cleaned and on_error then
        on_error("Codex returned an empty completion")
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
