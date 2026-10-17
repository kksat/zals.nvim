-- The client and server use the same Workspace boundary by default.
-- Override root_markers and ansible.workspace.rootMarker together.
return {
  cmd = { "zals", "--stdio" },
  filetypes = { "yaml.ansible", "jinja2" },
  root_markers = { ".git" },
  commands = require("zals.commands").commands,
  settings = {
    ansible = {
      ansible = {
        path = "ansible",
        useFullyQualifiedCollectionNames = true,
      },
      completion = {
        provideRedirectModules = true,
        provideModuleOptionAliases = true,
      },
      validation = {
        enabled = true,
        lint = {
          enabled = true,
          path = "ansible-lint",
          arguments = "",
          autoFixOnSave = false,
        },
      },
      python = {
        interpreterPath = "",
        activationScript = "",
        venvPath = ".venv",
      },
    },
  },
}
