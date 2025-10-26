local M = {}

function M.get_semantic_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local params = vim.lsp.util.make_position_params()

  local ctx = { code = {}, symbols = {} }

  -- Grab local code window (10 lines before/after)
  local start_line = math.max(0, cursor[1] - 10)
  local end_line = cursor[1]
  ctx.code = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)

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

