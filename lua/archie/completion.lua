local api = require("archie.api")
local lsp = require("archie.lsp_bridge")
local Job = require("plenary.job")

local M = {}

-- ghost namespace and state
local ghost_ns = vim.api.nvim_create_namespace("archie_ghost")
local ghost_enabled = false
local debounce_timer = nil
local debounce_delay = 250  -- ms delay after typing stops
local current_job = nil

---------------------------------------------------------------------
-- SETUP
---------------------------------------------------------------------
function M.setup(opts)
  opts = opts or {}
  if opts.autocomplete_delay then
    debounce_delay = opts.autocomplete_delay
  end
end

function M.is_enabled()
  return ghost_enabled
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function clear_ghost()
  vim.api.nvim_buf_clear_namespace(0, ghost_ns, 0, -1)
end

local function show_ghost(text)
  if not ghost_enabled or not text or text == "" then return end
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1

  text = text:gsub("^%s+", "")
  local preview = text:match("^[^\n]+") or text

  clear_ghost()
  vim.api.nvim_buf_set_extmark(buf, ghost_ns, line, -1, {
    virt_text = { { preview, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

---------------------------------------------------------------------
-- MODEL REQUEST
---------------------------------------------------------------------
local function request_completion()
  if not ghost_enabled then return end

  local ctx = lsp.get_semantic_context()
  local prompt = table.concat(ctx.code, "\n") .. "\n# Continue code:\n"

  -- cancel any ongoing job
  if current_job and not current_job.is_shutdown then
    pcall(current_job.shutdown, current_job)
  end

  current_job = Job:new({
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
      api.endpoint,
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

      local text = res.text
        or (res.choices and res.choices[1]
          and (res.choices[1].text or res.choices[1].content))
      if not text or text == "" then return end

      vim.schedule(function()
        show_ghost(text)
      end)
    end,
  })

  current_job:start()
end

---------------------------------------------------------------------
-- AUTOCOMPLETE HOOKS
---------------------------------------------------------------------
-- Triggered after typing stops for debounce_delay ms
local function debounced_suggest()
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
  end

  debounce_timer = vim.defer_fn(function()
    request_completion()
  end, debounce_delay)
end

-- Public API to trigger manually
function M.suggest()
  if not ghost_enabled then return end
  request_completion()
end

function M.toggle_ghost()
  ghost_enabled = not ghost_enabled
  if not ghost_enabled then
    clear_ghost()
    vim.notify("Archie autocomplete disabled", vim.log.levels.INFO)
    -- remove autocmds
    pcall(vim.api.nvim_del_autocmd, M._insert_autocmd)
  else
    vim.notify("Archie autocomplete enabled", vim.log.levels.INFO)

    -- set up autocmds to track typing
    local group = vim.api.nvim_create_augroup("ArchieAutoComplete", { clear = true })
    M._insert_autocmd = vim.api.nvim_create_autocmd("InsertCharPre", {
      group = group,
      callback = function()
        debounced_suggest()
      end,
    })
  end
end

return M
