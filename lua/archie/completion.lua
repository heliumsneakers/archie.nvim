local api = require("archie.api")
local lsp = require("archie.lsp_bridge")
local Job = require("plenary.job")

local M = {}

-- global state
local ghost_ns = vim.api.nvim_create_namespace("archie_ghost")
local ghost_enabled = true
local current_job = nil
local pending_text = nil
local debounce_timer = nil
local debounce_delay = 300

vim.api.nvim_set_hl(0, "ArchieGhostText", { fg = "#666666", italic = true })

---------------------------------------------------------------------
-- Setup & State
---------------------------------------------------------------------
function M.setup(opts)
  opts = opts or {}
  if opts.autocomplete_delay then debounce_delay = opts.autocomplete_delay end
  if opts.enable_autocomplete ~= nil then ghost_enabled = opts.enable_autocomplete end
end

function M.is_enabled()
  return ghost_enabled
end

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function clear_ghost()
  vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
  pending_text = nil
end

local function show_ghost(text)
  if not ghost_enabled or not text or text == "" then return end
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  text = text:gsub("^%s+", "")
  local preview = text:match("^[^\n]+") or text
  clear_ghost()
  pending_text = preview
  vim.api.nvim_buf_set_extmark(buf, ghost_ns, line, -1, {
    virt_text = { { preview, "ArchieGhostText" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  })
end

---------------------------------------------------------------------
-- Fault-tolerant JSON decoding
---------------------------------------------------------------------
local function safe_json_decode(raw)
  if not raw or raw == "" then return nil end
  local ok, decoded = pcall(vim.fn.json_decode, raw)
  if ok and type(decoded) == "table" then return decoded end

  local clean = raw:gsub("[%z\1-\31]", ""):gsub("\r", "")
  ok, decoded = pcall(vim.fn.json_decode, clean)
  if ok and type(decoded) == "table" then return decoded end

  local content = clean:match('"content"%s*:%s*"(.-)"')
    or clean:match('"text"%s*:%s*"(.-)"')
  if content then
    return { content = content:gsub("\\n", "\n"):gsub('\\"', '"') }
  end
  return nil
end

---------------------------------------------------------------------
-- Request completion
---------------------------------------------------------------------
local function request_completion()
  if not ghost_enabled then return end
  local ctx = lsp.get_semantic_context()
  if not ctx or not ctx.code then return end

  local prompt = table.concat(ctx.code, "\n") .. "\n# Continue code:\n"

  if current_job and not current_job.is_shutdown then
    pcall(current_job.shutdown, current_job)
  end

  current_job = Job:new({
    command = "curl",
    args = {
      "-sS", "--no-buffer",
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
        vim.schedule(function()
          vim.notify(("Archie request failed (exit %d): %s"):format(code or -1, stderr), vim.log.levels.ERROR)
        end)
        return
      end

      local res = safe_json_decode(stdout)
      if not res or type(res) ~= "table" then return end

      local text = res.content
        or res.text
        or (res.choices and res.choices[1]
          and (res.choices[1].text
            or (res.choices[1].message and res.choices[1].message.content)
            or res.choices[1].content))
        or res.response

      if not text or text == "" then return end
      vim.schedule(function() show_ghost(text) end)
    end,
  })
  current_job:start()
end

---------------------------------------------------------------------
-- Auto-update suggestions while typing (debounced)
---------------------------------------------------------------------
local function debounced_request()
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end
  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(debounce_delay, 0, function()
    vim.schedule(request_completion)
  end)
end

vim.api.nvim_create_autocmd("InsertCharPre", {
  callback = function()
    if ghost_enabled then
      debounced_request()
    end
  end,
  group = vim.api.nvim_create_augroup("ArchieAutoGhost", { clear = true }),
})

---------------------------------------------------------------------
-- Accept ghost text
---------------------------------------------------------------------
function M.accept_ghost()
  if not pending_text or pending_text == "" then return end
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  vim.api.nvim_buf_set_text(buf, line, -1, line, -1, { pending_text })
  clear_ghost()
end

---------------------------------------------------------------------
-- Keymap: Shift-Tab to accept current suggestion
---------------------------------------------------------------------
vim.keymap.set("i", "<S-Tab>", function()
  if ghost_enabled then
    M.accept_ghost()
  end
end, { desc = "Archie: accept ghost completion" })

---------------------------------------------------------------------
return M
