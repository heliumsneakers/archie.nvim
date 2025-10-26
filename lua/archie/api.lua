local M = {}
local Job = require("plenary.job")

M.endpoint = "http://127.0.0.1:8080/completion"

function M.setup(opts)
  if opts.endpoint then
    M.endpoint = opts.endpoint
  end
end

function M.query_async(prompt, callback)
  Job:new({
    command = "curl",
    args = {
      "-s",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", vim.fn.json_encode({
        prompt = prompt,
        max_tokens = 256,
        temperature = 0.2,
      }),
      M.endpoint,
    },
    on_exit = function(j, code)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("Archie API error", vim.log.levels.ERROR)
        end)
        return
      end

      local output = table.concat(j:result(), "\n")
      local ok, data = pcall(vim.fn.json_decode, output)
      if ok and data then
        callback(data)
      end
    end,
  }):start()
end

return M
