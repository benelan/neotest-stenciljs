local async = require("neotest.async")
local uv = vim.uv or vim.loop

local M = {}

M.is_windows = uv.os_uname().version:match("Windows")

function M.find_in_parent_node_modules(target, start, stop)
  return vim.fs.find(vim.fs.joinpath("node_modules", (unpack or table.unpack)(target)), {
    path = start,
    upward = true,
    limit = 1,
    stop = stop or vim.uv.os_homedir(),
  })[1]
end

-- Note: this function is almost entirely taken from https://github.com/nvim-neotest/neotest/blob/master/lua/neotest/lib/file/init.lua#L93-L144
-- The only difference is that neotest function reads only new lines and this one reads and returns the whole file
--- Streams data from a file, watching for new data over time
--- Each time new data arrives function reads whole file and returns its content
--- Useful for watching a file which is written to by another process.
---@async
---@param file_path string
---@return (fun(): string, fun()) Iterator and callback to stop streaming
function M.stream(file_path)
  local queue = async.control.queue()
  local read_semaphore = async.control.semaphore(1)

  ---@diagnostic disable-next-line: param-type-mismatch
  local open_err, file_fd = async.uv.fs_open(file_path, "r", 438)
  assert(not open_err, open_err)
  assert(file_fd, "unable to open file: " .. file_path)

  local exit_future = async.control.future()
  local read = function()
    read_semaphore.with(function()
      local stat_err, stat = async.uv.fs_fstat(file_fd)
      assert(not stat_err, stat_err)
      assert(stat, "unable to stat file: " .. file_path)

      local read_err, data = async.uv.fs_read(file_fd, stat.size, 0)
      assert(not read_err, read_err)
      queue.put(data)
    end)
  end

  read()
  local event = vim.loop.new_fs_event()
  assert(event, "unable to create new filesystem event")

  event:start(file_path, {}, function(err, _, _)
    assert(not err)
    async.run(read)
  end)

  local function stop()
    exit_future.wait()
    event:stop()
    local close_err = async.uv.fs_close(file_fd)
    assert(not close_err, close_err)
  end

  async.run(stop)

  return queue.get, exit_future.set
end

return M
