local M = {}

function M.get_semantic_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local params = vim.lsp.util.make_position_params()

  local ctx = {
    code = {},
    symbols = {},
    filetype = vim.bo[bufnr].filetype,
    cursor = { row = cursor[1], col = cursor[2] },
  }

  -- Grab local code window (10 lines before/after)
  local start_line = math.max(0, cursor[1] - 10)
  local end_line = cursor[1]
  ctx.code = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)

  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
  local col = cursor[2]
  ctx.line_prefix = line:sub(1, col)
  ctx.line_suffix = line:sub(col + 1)

  -- Optionally include symbols
  local results = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", params, 200)
  if results then
    for _, res in pairs(results) do
      vim.list_extend(ctx.symbols, res.result or {})
    end
  end

  return ctx
end

return M
