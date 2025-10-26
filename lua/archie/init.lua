local M = {}

function M.setup(opts)
  opts = opts or {}
  require("archie.api").setup(opts)
  require("archie.completion").setup(opts)
  require("archie.ui").setup(opts)

  -- Command: open prompt window
  vim.api.nvim_create_user_command("QwenAsk", function()
    require("archie.ui").open_prompt_window()
  end, {})

  -- Keymap: ghost text toggle
  vim.keymap.set("i", "<C-g>", function()
    require("archie.completion").toggle_ghost()
  end, { desc = "Toggle Qwen ghost text" })

  -- Optional manual trigger
  vim.keymap.set("i", "<C-Space>", function()
    require("archie.completion").suggest()
  end, { desc = "Trigger Qwen completion" })
end

return M

