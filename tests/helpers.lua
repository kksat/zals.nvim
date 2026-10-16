vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("filetype on")

local M = { count = 0 }
M.temp = vim.fn.tempname()
vim.fn.mkdir(M.temp .. "/workspace/.git", "p")
M.temp = assert(vim.uv.fs_realpath(M.temp))
M.root = M.temp .. "/workspace"

function M.equal(actual, expected, message)
  M.count = M.count + 1
  assert(vim.deep_equal(actual, expected), (message or "values differ") .. "\nexpected: "
    .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end

function M.write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines or { "---" }, path) == 0)
end

function M.open(path, filetype)
  M.write(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  if filetype then
    M.equal(vim.bo.filetype, filetype, path)
  end
  return vim.api.nvim_get_current_buf()
end

function M.client(bufnr)
  assert(vim.wait(5000, function()
    local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "zals" })
    return #clients == 1 and clients[1].initialized
  end), "zals did not attach to " .. vim.api.nvim_buf_get_name(bufnr))
  return vim.lsp.get_clients({ bufnr = bufnr, name = "zals" })[1]
end

function M.run(fn)
  local ok, err = xpcall(fn, debug.traceback)
  vim.lsp.enable("zals", false)
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end
  vim.wait(2000, function()
    return #vim.lsp.get_clients() == 0
  end)
  vim.fn.delete(M.temp, "rf")
  if not ok then
    error(err)
  end
  print(("Passed %d assertions"):format(M.count))
end

return M
