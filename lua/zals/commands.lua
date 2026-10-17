local M = {}

---Validate a short Ansible role name (`^[a-z][a-z0-9_]*$`, without dots).
---@param value string?
---@return string? name, string? err
function M.validate_role_name(value)
  local trimmed = vim.trim(value or "")
  if trimmed == "" then
    return nil, "Role name is required"
  end
  if trimmed:find(".", 1, true) then
    return nil, "Enter only the short role name without dots; collection namespace and name are added automatically"
  end
  if not trimmed:match("^[a-z][a-z0-9_]*$") then
    return nil, "Role name must start with a lowercase letter and contain only lowercase letters, digits, and underscores"
  end
  return trimmed, nil
end

---Prompt for role name and target `roles/` directory, then execute `command_name` on the server.
---@param client vim.lsp.Client
---@param bufnr integer
---@param command_name string
---@param base_arg table
function M.prompt_and_execute(client, bufnr, command_name, base_arg)
  if type(base_arg.name) == "string" and base_arg.name ~= "" and type(base_arg.targetDir) == "string" and base_arg.targetDir ~= "" then
    client:request("workspace/executeCommand", {
      command = command_name,
      arguments = { base_arg },
    }, function(err)
      if err then
        vim.notify("zals: " .. (err.message or tostring(err)), vim.log.levels.ERROR)
      end
    end, bufnr)
    return
  end

  local candidates = base_arg.candidates or {}
  if #candidates == 0 then
    vim.notify("zals: no candidate roles/ directories found", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({ prompt = "Role name: " }, function(input)
    if not input or vim.trim(input) == "" then
      return
    end
    local name, err = M.validate_role_name(input)
    if not name then
      vim.notify("zals: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.ui.select(candidates, {
      prompt = "Select destination roles/ directory:",
      format_item = function(item)
        return string.format("%s (%s)", item.label, item.dir)
      end,
    }, function(picked)
      if not picked then
        return
      end
      local arg = vim.tbl_extend("force", base_arg, {
        name = name,
        targetDir = picked.dir,
      })
      if type(picked.collection) == "string" and picked.collection ~= "" then
        arg.collection = picked.collection
      else
        arg.collection = nil
      end
      client:request("workspace/executeCommand", {
        command = command_name,
        arguments = { arg },
      }, function(req_err)
        if req_err then
          vim.notify("zals: " .. (req_err.message or tostring(req_err)), vim.log.levels.ERROR)
        end
      end, bufnr)
    end)
  end)
end

---@param command_name string
local function make_command_handler(command_name)
  ---@param command lsp.Command
  ---@param ctx lsp.HandlerContext
  return function(command, ctx)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if not client then
      return
    end
    local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()
    local arg = (command.arguments and command.arguments[1]) or {}
    M.prompt_and_execute(client, bufnr, command_name, arg)
  end
end

M.commands = {
  ["zals.extractToRole"] = make_command_handler("zals.extractToRole"),
  ["zals.createRole"] = make_command_handler("zals.createRole"),
}

---Query candidate `roles/` locations from `zals`, prompt for name and location, and create the role.
---@param bufnr? integer
function M.create_role(bufnr)
  bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "zals" })
  local client = clients[1] or vim.lsp.get_clients({ name = "zals" })[1]
  if not client then
    vim.notify("zals client is not attached", vim.log.levels.ERROR)
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local uri = name ~= "" and vim.uri_from_fname(name) or nil
  local query_arg = uri and { uri = uri } or vim.empty_dict()

  client:request("workspace/executeCommand", {
    command = "zals.createRole",
    arguments = { query_arg },
  }, function(err, result)
    if err then
      vim.notify("zals: " .. (err.message or tostring(err)), vim.log.levels.ERROR)
      return
    end
    local base_arg = { candidates = (result and result.candidates) or {} }
    if uri then
      base_arg.uri = uri
    end
    M.prompt_and_execute(client, bufnr, "zals.createRole", base_arg)
  end, bufnr)
end

return M
