local M = {}

local menu_win = nil
local menu_buf = nil
local menu_items = { "Prompt Model", "Toggle Autocomplete" }

function M.setup(opts)
  opts = opts or {}
  require("archie.api").setup(opts)
  require("archie.completion").setup(opts)
  require("archie.ui").setup(opts)

  -- Keymap: open Archie menu (Shift + \)
  vim.keymap.set("n", "<Bar>", function()
    M.open_menu()
  end, { desc = "Open Archie menu" })
end

-- Helper to close the menu window
local function close_menu()
  if menu_win and vim.api.nvim_win_is_valid(menu_win) then
    vim.api.nvim_win_close(menu_win, true)
  end
  menu_win = nil
  menu_buf = nil
end

-- Redraw menu with current state
local function render_menu()
  if not menu_buf then return end
  local ghost_on = require("archie.completion").is_enabled()

  local lines = {
    string.format("%s %s", "→", "Archie Menu"),
    "",
    string.format("%s  %s", "1.", "Prompt Model"),
    string.format("%s  %s %s", "2.", "Autocomplete", ghost_on and "✔" or "✖"),
    "",
    "Press q or Esc to close",
  }

  vim.api.nvim_buf_set_lines(menu_buf, 0, -1, false, lines)
end

function M.open_menu()
  -- If already open, close it
  if menu_win and vim.api.nvim_win_is_valid(menu_win) then
    close_menu()
    return
  end

  menu_buf = vim.api.nvim_create_buf(false, true)

  local width = 35
  local height = 7
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  menu_win = vim.api.nvim_open_win(menu_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    style = "minimal",
    title = " Archie ",
    title_pos = "center",
  })

  vim.bo[menu_buf].modifiable = false
  vim.bo[menu_buf].bufhidden = "wipe"
  vim.keymap.set("n", "q", close_menu, { buffer = menu_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_menu, { buffer = menu_buf, nowait = true })

  -- Keybinds for menu actions
  vim.keymap.set("n", "1", function()
    close_menu()
    require("archie.ui").open_prompt_window()
  end, { buffer = menu_buf, nowait = true })

  vim.keymap.set("n", "2", function()
    require("archie.completion").toggle_ghost()
    render_menu()
  end, { buffer = menu_buf, nowait = true })

  render_menu()
end

return M
