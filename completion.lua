local api = require("qwen_coder.api")
local lsp = require("qwen_coder.lsp_bridge")

local M = {}
local ghost_ns = vim.api.nvim_create_namespace("qwen_ghost")
local ghost_enabled = false

function M.setup(_) end

function M.toggle_ghost()
  ghost_enabled = not ghost_enabled
  if not ghost_enabled then
    vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
    vim.notify("Qwen ghost disabled", vim.log.levels.INFO)
  else
    vim.notify("Qwen ghost enabled", vim.log.levels.INFO)
    M.suggest()
  end
end

function M.suggest()
  if not ghost_enabled then return end

  local ctx = lsp.get_semantic_context()
  local prompt = table.concat(ctx.code, "\n") .. "\n# Continue code:\n"

  api.query_async(prompt, function(res)
    local text = res.text or (res.choices and res.choices[1].text)
    if not text then return end

    vim.schedule(function()
      vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      vim.api.nvim_buf_set_extmark(0, ghost_ns, line, 0, {
        virt_text = { { text:gsub("\n.*", ""), "Comment" } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end)
  end)
end

return M

