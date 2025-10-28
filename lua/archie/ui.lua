local api = require("archie.api")
local lsp = require("archie.lsp_bridge")

local M = {}

function M.setup(_) end

function M.open_prompt_window()
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.5)
  local height = 3
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_keymap(buf, "i", "<CR>", "", {
    noremap = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local query = table.concat(lines, " ")
      vim.api.nvim_win_close(win, true)
      M._run_query(query)
    end,
  })

  vim.cmd("startinsert")
end

function M._run_query(query)
  local ctx = lsp.get_semantic_context()
  local prompt = table.concat(ctx.code, "\n") .. "\n# " .. query .. "\n"

  api.query_async(prompt, function(res)
    local text = res.text or (res.choices and res.choices[1].text)
    if not text then return end

    vim.schedule(function()
      vim.api.nvim_put(vim.split(text, "\n"), "l", true, true)
    end)
  end, nil, { cwd = ctx.project_root or ctx.cwd })
end

return M
