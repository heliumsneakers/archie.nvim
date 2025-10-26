local M = {}

function M.setup(opts)
  opts = opts or {}
  require("qwen_coder.api").setup(opts)
  require("qwen_coder.completion").setup(opts)
  require("qwen_coder.ui").setup(opts)

  -- Command: open prompt window
  vim.api.nvim_create_user_command("QwenAsk", function()
    require("qwen_coder.ui").open_prompt_window()
  end, {})

  -- Keymap: ghost text toggle
  vim.keymap.set("i", "<C-g>", function()
    require("qwen_coder.completion").toggle_ghost()
  end, { desc = "Toggle Qwen ghost text" })

  -- Optional manual trigger
  vim.keymap.set("i", "<C-Space>", function()
    require("qwen_coder.completion").suggest()
  end, { desc = "Trigger Qwen completion" })
end

return M

