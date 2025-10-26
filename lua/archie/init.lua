-- lua/archie/init.lua
local M = {}

local menu_win, menu_buf

local function close_menu()
  if menu_win and vim.api.nvim_win_is_valid(menu_win) then
    vim.api.nvim_win_close(menu_win, true)
  end
  menu_win, menu_buf = nil, nil
end

local function render_menu()
  if not menu_buf then return end
  vim.bo[menu_buf].modifiable = true
  local ghost_on = require("archie.completion").is_enabled()
  local lines = {
    "  ⚙  Archie Menu",
    "",
    "  1.  Prompt Model",
    string.format("  2.  Autocomplete  %s", ghost_on and "✔" or "✖"),
    "",
    "  q / Esc  →  Close menu",
  }
  vim.api.nvim_buf_set_lines(menu_buf, 0, -1, false, lines)
  vim.bo[menu_buf].modifiable = false
end

function M.open_menu()
  if menu_win and vim.api.nvim_win_is_valid(menu_win) then
    close_menu()
    return
  end
  menu_buf = vim.api.nvim_create_buf(false, true)
  local width, height = 36, 7
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

  vim.bo[menu_buf].bufhidden = "wipe"

  vim.keymap.set("n", "q", close_menu, { buffer = menu_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_menu, { buffer = menu_buf, nowait = true })

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

function M.setup(opts)
  opts = opts or {}
  require("archie.api").setup(opts)
  require("archie.completion").setup(opts)
  require("archie.ui").setup(opts)

  vim.keymap.set("n", "<Space>|", function()
    M.open_menu()
  end, { desc = "Open Archie menu" })
end

return M
