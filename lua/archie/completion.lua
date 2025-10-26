local api = require("archie.api")
local lsp = require("archie.lsp_bridge")
local Job = require("plenary.job")

local M = {}

---------------------------------------------------------------------
-- GLOBAL STATE / HIGHLIGHT
---------------------------------------------------------------------
local ghost_ns = vim.api.nvim_create_namespace("archie_ghost")
local ghost_enabled = false
local debounce_timer = nil
local debounce_delay = 250 -- ms delay after typing stops
local current_job = nil

vim.api.nvim_set_hl(0, "ArchieGhostText", { fg = "#666666", italic = true })

---------------------------------------------------------------------
-- SETUP
---------------------------------------------------------------------
function M.setup(opts)
  opts = opts or {}
  if opts.autocomplete_delay then
    debounce_delay = opts.autocomplete_delay
  end
end

function M.is_enabled()
  return ghost_enabled
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function clear_ghost()
  vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
end

local function show_ghost(text)
  if not ghost_enabled or not text or text == "" then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  text = text:gsub("^%s+", "")
  local preview = text:match("^[^\n]+") or text

  clear_ghost()
  vim.api.nvim_buf_set_extmark(buf, ghost_ns, line, -1, {
    virt_text = { { preview, "ArchieGhostText" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  })
end

---------------------------------------------------------------------
-- STRONG JSON SANITIZER
---------------------------------------------------------------------
local function sanitize_json(raw)
  if not raw or raw == "" then
    return "{}"
  end

  -- Keep only the last full JSON block
  local last_obj = raw:match("(%b{})%s*$")
  if last_obj then
    raw = last_obj
  end

  -- Normalize CRLF → LF
  raw = raw:gsub("\r\n", "\n")

  -- Escape literal newlines inside quoted strings
  local fixed = {}
  local in_string = false
  for c in raw:gmatch(".") do
    if c == '"' then
      table.insert(fixed, c)
      in_string = not in_string
    elseif in_string and c == "\n" then
      table.insert(fixed, "\\n")
    else
      table.insert(fixed, c)
    end
  end
  raw = table.concat(fixed)

  -- Ensure closing brace
  if not raw:match("}%s*$") then
    raw = raw .. "}"
  end

  return raw
end

---------------------------------------------------------------------
-- MODEL REQUEST
---------------------------------------------------------------------
local function request_completion()
  if not ghost_enabled then
    return
  end

  local ctx = lsp.get_semantic_context()
  if not ctx or not ctx.code then
    return
  end

  local prompt = table.concat(ctx.code, "\n") .. "\n# Continue code:\n"

  -- Cancel previous job if running
  if current_job and not current_job.is_shutdown then
    pcall(current_job.shutdown, current_job)
  end

  current_job = Job:new({
    command = "curl",
    args = {
      "--no-buffer",
      "-sS",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", vim.fn.json_encode({
        prompt = prompt,
        n_predict = 64,
        temperature = 0.2,
        stream = false,
      }),
      api.endpoint,
    },
    on_exit = function(j, code)
      local stdout = table.concat(j:result(), "\n")
      local stderr = table.concat(j:stderr_result(), "\n")

      if not code or code ~= 0 then
        local exit_code = code or -1
        vim.schedule(function()
          vim.notify(
            string.format(
              "Archie model request failed (exit %d)\nSTDOUT: %s\nSTDERR: %s",
              exit_code,
              stdout ~= "" and stdout or "<empty>",
              stderr ~= "" and stderr or "<empty>"
            ),
            vim.log.levels.ERROR
          )
        end)
        return
      end


      -- Sanitize malformed JSON output
      local sanitized = sanitize_json(stdout)
      local ok, res = pcall(vim.fn.json_decode, sanitized)
      if not ok or type(res) ~= "table" then
        -- Try again with stripped control characters (fix: valid Lua pattern)
        local alt = sanitized:gsub("[%z\1-\31]", "")
        ok, res = pcall(vim.fn.json_decode, alt)
      end
      if not ok or type(res) ~= "table" then
        vim.schedule(function()
          vim.notify("Archie: invalid JSON response:\n" .. sanitized, vim.log.levels.ERROR)
        end)
        return
      end

      -- Extract text from model response
      local text = res.content
      or res.text
      or (res.choices and res.choices[1]
      and (res.choices[1].text
      or (res.choices[1].message and res.choices[1].message.content)
      or res.choices[1].content))
      or res.response

      if not text or text == "" then
        return
      end

      vim.schedule(function()
        show_ghost(text)
      end)
    end,
  })

  current_job:start()
end

---------------------------------------------------------------------
-- AUTOCOMPLETE HOOKS
---------------------------------------------------------------------
local function debounced_suggest()
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end

  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(debounce_delay, 0, function()
    vim.schedule(request_completion)
  end)
end

function M.suggest()
  if not ghost_enabled then
    return
  end
  request_completion()
end

function M.toggle_ghost()
  ghost_enabled = not ghost_enabled
  if not ghost_enabled then
    clear_ghost()
    if debounce_timer and not debounce_timer:is_closing() then
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil
    end
    vim.notify("Archie autocomplete disabled", vim.log.levels.INFO)
    pcall(vim.api.nvim_del_autocmd, M._insert_autocmd)
  else
    vim.notify("Archie autocomplete enabled", vim.log.levels.INFO)
    local group = vim.api.nvim_create_augroup("ArchieAutoComplete", { clear = true })
    M._insert_autocmd = vim.api.nvim_create_autocmd("InsertCharPre", {
      group = group,
      callback = function()
        debounced_suggest()
      end,
    })
  end
end

---------------------------------------------------------------------
-- ACCEPT GHOST TEXT
---------------------------------------------------------------------
function M.accept_ghost()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local extmarks =
  vim.api.nvim_buf_get_extmarks(buf, ghost_ns, { line, 0 }, { line, -1 }, { details = true })
  if #extmarks == 0 then
    return
  end

  local details = extmarks[1][4]
  local text = details.virt_text and details.virt_text[1][1]
  if not text or text == "" then
    return
  end

  vim.api.nvim_buf_set_text(buf, line, -1, line, -1, { text })
  clear_ghost()
end

vim.keymap.set("i", "<Tab>", function()
  require("archie.completion").accept_ghost()
end, { desc = "Accept Archie ghost text" })

---------------------------------------------------------------------
return M
