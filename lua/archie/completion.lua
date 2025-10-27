local api = require("archie.api")
local lsp = require("archie.lsp_bridge")

local M = {}

local ghost_ns = vim.api.nvim_create_namespace("archie_ghost")
local ghost_enabled = true
local current_job = nil
local pending_lines = nil
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

local function has_values(tbl)
  return type(tbl) == "table" and next(tbl) ~= nil
end

local function clear_ghost()
  vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
  pending_lines = nil
end

local function show_ghost(text)
  if not ghost_enabled or not text or text == "" then return end
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local lines = vim.split(text, "\n", { plain = true })
  if #lines == 0 then return end

  clear_ghost()
  pending_lines = lines

  local preview = lines[1]
  vim.api.nvim_buf_set_extmark(buf, ghost_ns, row, col, {
    virt_text = { { preview, "ArchieGhostText" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  })
end

local function cancel_job()
  if current_job and not current_job.is_shutdown then
    pcall(current_job.shutdown, current_job)
  end
  current_job = nil
end

local function request_completion()
  if not ghost_enabled then return end
  local ctx = lsp.get_semantic_context()
  if not ctx or not has_values(ctx.code) then return end

  cancel_job()
  current_job = api.request_inline_completion(ctx, function(text)
    current_job = nil
    vim.schedule(function()
      show_ghost(text)
    end)
  end, function(err)
    current_job = nil
    if err and err ~= "" then
      vim.schedule(function()
        vim.notify("Archie completion error: " .. err, vim.log.levels.ERROR)
      end)
    end
  end)
end

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

function M.accept_ghost()
  if not has_values(pending_lines) then return end
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  vim.api.nvim_buf_set_text(buf, row, col, row, col, pending_lines)
  clear_ghost()
end

vim.keymap.set("i", "<S-Tab>", function()
  if ghost_enabled then
    M.accept_ghost()
  end
end, { desc = "Archie: accept ghost completion" })

return M
