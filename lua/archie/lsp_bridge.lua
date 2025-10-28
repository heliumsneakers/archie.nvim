local M = {}

local protocol = vim.lsp.protocol or {}
local symbol_kind_names = protocol.SymbolKind or {}

local function kind_name(kind)
  if type(kind) == "number" and symbol_kind_names[kind] then
    return symbol_kind_names[kind]
  end
  if type(kind) == "string" then return kind end
  return "Unknown"
end

local function push_symbol_line(acc, depth, sym)
  local indent = string.rep("  ", depth)
  local name = sym.name or sym.detail or ""
  if name == "" then return end
  table.insert(acc, ("%s%s (%s)"):format(indent, name, kind_name(sym.kind)))
end

local function collect_symbols(list, acc, depth, limit)
  if type(list) ~= "table" then return end
  depth = depth or 0
  limit = limit or 20
  for _, sym in ipairs(list) do
    if #acc >= limit then return end
    if type(sym) == "table" then
      push_symbol_line(acc, depth, sym)
      if type(sym.children) == "table" and #sym.children > 0 then
        collect_symbols(sym.children, acc, depth + 1, limit)
      end
    end
  end
end

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

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath ~= "" then
    ctx.filepath = filepath
    local relative = vim.fn.fnamemodify(filepath, ":.")
    if relative == filepath then
      relative = vim.fn.fnamemodify(filepath, ":~")
    end
    ctx.relative_path = relative
  end

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
    local summary = {}
    collect_symbols(ctx.symbols, summary, 0, 30)
    if #summary > 0 then ctx.symbol_summary = summary end
  end

  return ctx
end

return M
