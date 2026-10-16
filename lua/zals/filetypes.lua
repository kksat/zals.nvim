-- Adapted from kksat/zals docs/examples/neovim-role-filetypes.lua (GPL-3.0-only).
local role_dirs = { "defaults", "vars", "tasks", "handlers", "meta", "templates" }

-- A standalone Role need not live under roles/<name>/.
local function role_filetype(path, filetype)
  local dir = vim.fs.dirname(path)
  while dir do
    if vim.tbl_contains(role_dirs, vim.fs.basename(dir)) then
      local role = vim.fs.dirname(dir)
      if role and (
        vim.fs.basename(vim.fs.dirname(role) or "") == "roles"
        or vim.fn.filereadable(role .. "/meta/main.yml") == 1
        or vim.fn.filereadable(role .. "/meta/main.yaml") == 1
      ) then
        return filetype
      end
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
end

local rules = {
  filename = {},
  pattern = {
    [".*/roles/[^/]+/.*%.ya?ml"] = "yaml.ansible",
    [".*/ansible_collections/[^/]+/[^/]+/.*%.ya?ml"] = "yaml.ansible",
    [".*/playbooks/.*%.ya?ml"] = "yaml.ansible",
  },
}

for _, name in ipairs({ "requirements", "execution-environment", "galaxy", "site" }) do
  for _, extension in ipairs({ "yml", "yaml" }) do
    rules.filename[name .. "." .. extension] = "yaml.ansible"
  end
end

for _, directory in ipairs(role_dirs) do
  rules.pattern[".*/" .. directory .. "/.*%.ya?ml"] = {
    function(path)
      return role_filetype(path, "yaml.ansible")
    end,
    { priority = 10 },
  }
end
rules.pattern[".*/templates/.*%.j2"] = {
  function(path)
    return role_filetype(path, "jinja2")
  end,
  { priority = 10 },
}

return rules
