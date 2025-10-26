local api = require("archie.api")
local lsp = require("archie.lsp_bridge")
local Job = require("plenary.job")

local M = {}

-- ghost namespace
local ghost_ns = vim.api.nvim_create_namespace("archie_ghost")
local ghost_enabled = false

function M.is_enabled()
  return ghost_enabled
end

-- clear ghost text
local function clear_ghost()
  vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
end

-- render ghost text at cursor line
local function show_ghost(text)
  if not ghost_enabled or not text or text == "" then return end
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1

  -- trim leading newlines/spaces
  text = text:gsub("^%s+", "")
  local preview = text:match("^[^\n]+") or text

  clear_ghost()

  vim.api.nvim_buf_set_extmark(buf, ghost_ns, line, -1, {
    virt_text = { { preview, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

-- async model query
function M.suggest()
  if not ghost_enabled then return end

  local ctx = lsp.get_semantic_context()
  local prompt = table.concat(ctx.code, "\n") .. "\n# Continue code:\n"

  Job:new({
    command = "curl",
    args = {
      "-s",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", vim.fn.json_encode({
        prompt = prompt,
        max_tokens = 64,
        temperature = 0.2,
      }),
      "http://127.0.0.1:8080/completion",
    },
    on_exit = function(j, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("Archie model request failed", vim.log.levels.ERROR)
        end)
        return
      end

      local output = table.concat(j:result(), "\n")
      local ok, res = pcall(vim.fn.json_decode, output)
      if not ok or not res then return end

      -- handle both llama.cpp and OpenAI-like responses
      local text = res.text or (res.choices and res.choices[1] and (res.choices[1].text or res.choices[1].content))
      if not text or text == "" then return end

      vim.schedule(function()
        show_ghost(text)
      end)
    end,
  }):start()
end

function M.toggle_ghost()
  ghost_enabled = not ghost_enabled
  if not ghost_enabled then
    clear_ghost()
    vim.notify("Archie autocomplete disabled", vim.log.levels.INFO)
  else
    vim.notify("Archie autocomplete enabled", vim.log.levels.INFO)
    M.suggest()
  end
end

return M
