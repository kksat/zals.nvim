local M = {}

---@class zals.Options
---@field enabled? boolean Enable zals automatically (default true).
---@field filetype_detection? table|false Extra vim.filetype.add rules, or false to skip detection.
---@field lsp? vim.lsp.Config Overrides for the native zals LSP configuration.

---Register Ansible filetypes and configure Neovim's native LSP client.
---@param opts? zals.Options
function M.setup(opts)
  if vim.fn.has("nvim-0.11") ~= 1 then
    error("zals.nvim requires Neovim 0.11 or newer")
  end
  opts = opts or {}

  if opts.filetype_detection ~= false then
    vim.filetype.add(vim.tbl_deep_extend("force", require("zals.filetypes"), opts.filetype_detection or {}))
  end

  local commands = require("zals.commands")
  for name, handler in pairs(commands.commands) do
    vim.lsp.commands[name] = handler
  end
  vim.api.nvim_create_user_command("ZalsCreateRole", function()
    commands.create_role()
  end, { desc = "Create a new Ansible role with zals" })

  vim.lsp.config("zals", opts.lsp or {})
  if opts.enabled ~= false then
    vim.lsp.enable("zals")
  end
end

function M.create_role(bufnr)
  return require("zals.commands").create_role(bufnr)
end

return M
