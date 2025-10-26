local api = require("archie.api")
local lsp = require("archie.lsp_bridge")
local Job = require("plenary.job")

local M = {}

---------------------------------------------------------------------
-- GLOBAL STATE / HIGHLIGHT
---------------------------------------------------------------------
local ghost_ns = vim.api.nvim_create_namespace("archie_ghost")
local ghost_enabled = false
local debounce_timer = nil
local debounce_delay = 250 -- ms delay after typing stops
local current_job = nil

vim.api.nvim_set_hl(0, "ArchieGhostText", { fg = "#666666", italic = true })

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
    virt_text = { { preview, "ArchieGhostText" } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  })
end

---------------------------------------------------------------------
-- JSON RECOVERY HELPERS
---------------------------------------------------------------------
local function clean_json(raw)
  if not raw or raw == "" then return "{}" end
  -- keep only last full {...}
  local candidate = raw:match("(%b{})%s*$") or raw
  -- normalize newlines
  candidate = candidate:gsub("\r", "")
  -- remove ASCII control chars
  candidate = candidate:gsub("[%z\1-\31]", "")
  return candidate
end

local function extract_fallback(raw)
  -- try "content": "..."
  local match = raw:match('"content"%s*:%s*"(.-)"')
    or raw:match('"text"%s*:%s*"(.-)"')
  if match then
    return match:gsub("\\n", "\n"):gsub('\\"', '"')
  end
  return nil
end

---------------------------------------------------------------------
-- MODEL REQUEST
---------------------------------------------------------------------
local function request_completion()
  if not ghost_enabled then return end

  local ctx = lsp.get_semantic_context()
  if not ctx or not ctx.code then return end

  local prompt = table.concat(ctx.code, "\n") .. "\n# Continue code:\n"

  -- Cancel previous running job
  if current_job and not current_job.is_shutdown then
    pcall(current_job.shutdown, current_job)
  end

  current_job = Job:new({
    command = "curl",
    args = {
      "-sS", "--no-buffer",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", vim.fn.json_encode({
        prompt = prompt,
        n_predict = 64,
        temperature = 0.2,
        stream = false,
      }),
      api.endpoint,
    },

    on_exit = function(j, code)
      local stdout = table.concat(j:result(), "\n")
      local stderr = table.concat(j:stderr_result(), "\n")

      if not code or code ~= 0 then
        vim.schedule(function()
          vim.notify(
            string.format("Archie model request failed (exit %d)\n%s", code or -1, stderr),
            vim.log.levels.ERROR
          )
        end)
        return
      end

      local json_text = clean_json(stdout)
      local ok, res = pcall(vim.fn.json_decode, json_text)

      -- try recovery
      if not ok or type(res) ~= "table" then
        local recovered = extract_fallback(json_text)
        if recovered and recovered ~= "" then
          vim.schedule(function() show_ghost(recovered) end)
          return
        end
        vim.schedule(function()
          vim.notify("Archie: invalid JSON response:\n" .. json_text, vim.log.levels.ERROR)
        end)
        return
      end

      -- parse valid JSON
      local text = res.content
        or res.text
        or (res.choices and res.choices[1]
          and (res.choices[1].text
            or (res.choices[1].message and res.choices[1].message.content)
            or res.choices[1].content))
        or res.response

      if not text or text == "" then return end
      vim.schedule(function() show_ghost(text) end)
    end,
  })

  current_job:start()
end

---------------------------------------------------------------------
-- AUTOCOMPLETE HOOKS
---------------------------------------------------------------------
local function debounced_suggest()
  if debounce_timer and not debounce_timer:is_closing() then
    debounce_timer:stop()
    debounce_timer:close()
  end
  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(debounce_delay, 0, function()
    vim.schedule(request_completion)
  end)
end

function M.suggest()
  if ghost_enabled then request_completion() end
end

function M.toggle_ghost()
  ghost_enabled = not ghost_enabled
  if not ghost_enabled then
    clear_ghost()
    if debounce_timer and not debounce_timer:is_closing() then
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil
    end
    vim.notify("Archie autocomplete disabled", vim.log.levels.INFO)
    pcall(vim.api.nvim_del_autocmd, M._insert_autocmd)
  else
    vim.notify("Archie autocomplete enabled", vim.log.levels.INFO)
    local group = vim.api.nvim_create_augroup("ArchieAutoComplete", { clear = true })
    M._insert_autocmd = vim.api.nvim_create_autocmd("InsertCharPre", {
      group = group,
      callback = function() debounced_suggest() end,
    })
  end
end

---------------------------------------------------------------------
-- ACCEPT GHOST TEXT
---------------------------------------------------------------------
function M.accept_ghost()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local extmarks = vim.api.nvim_buf_get_extmarks(
    buf, ghost_ns, { line, 0 }, { line, -1 }, { details = true }
  )
  if #extmarks == 0 then return end
  local details = extmarks[1][4]
  local text = details.virt_text and details.virt_text[1][1]
  if not text or text == "" then return end
  vim.api.nvim_buf_set_text(buf, line, -1, line, -1, { text })
  clear_ghost()
end

vim.keymap.set("i", "<Tab>", function()
  require("archie.completion").accept_ghost()
end, { desc = "Accept Archie ghost text" })

---------------------------------------------------------------------
return M
