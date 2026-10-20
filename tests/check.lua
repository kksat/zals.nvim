local t = dofile("tests/helpers.lua")

-- A small in-process LSP transport: tests native attachment without requiring
-- a server binary, Ansible, Python, a plugin manager, or network access.
local starts = 0
local executed_commands = {}
local mock_candidates = {}
local function transport(dispatchers)
  starts = starts + 1
  local closing, request_id = false, 0
  return {
    request = function(method, params, callback)
      request_id = request_id + 1
      vim.schedule(function()
        if method == "initialize" then
          callback(nil, {
            capabilities = {
              textDocumentSync = 1,
              executeCommandProvider = { commands = { "zals.createRole", "zals.extractToRole" } },
            },
          })
          return
        end
        if method == "workspace/executeCommand" then
          executed_commands[#executed_commands + 1] = params
          local arg = params.arguments and params.arguments[1] or {}
          if params.command == "zals.createRole" and not arg.name then
            callback(nil, { candidates = mock_candidates })
            return
          end
          callback(nil, { ok = true })
          return
        end
        callback(nil, nil)
      end)
      return true, request_id
    end,
    notify = function(method)
      if method == "exit" then
        closing = true
        vim.schedule(function()
          dispatchers.on_exit(0, 0)
        end)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
      vim.schedule(function()
        dispatchers.on_exit(0, 0)
      end)
    end,
  }
end

t.run(function()
  for _, path in ipairs(vim.fn.glob("**/*.lua", false, true)) do
    assert(loadfile(path))
  end

  -- Neovim terminals export NVIM as a server socket, not an executable.
  -- Exercise Make's variable resolution without recursively running tests.
  local env = vim.fn.environ()
  env.NVIM = t.temp .. "/nvim.sock"
  env.NVIM_BIN = nil
  env.MAKEFLAGS, env.MFLAGS, env.MAKELEVEL = nil, nil, nil
  for _, target in ipairs({ "check", "integration" }) do
    for _, binary in ipairs({ "nvim", "/custom/neovim" }) do
      local args = { "make", "--no-print-directory", "--dry-run", target }
      if binary ~= "nvim" then
        args[#args + 1] = "NVIM_BIN=" .. binary
      end
      local result = vim.system(args, { env = env, clear_env = true }):wait()
      t.equal(result.code, 0, result.stderr)
      t.equal(result.stdout:find(env.NVIM, 1, true), nil, target .. ": must not execute the NVIM socket")
      t.equal(result.stdout:find(binary .. " --headless", 1, true) ~= nil, true,
        target .. ": select the default binary or explicit NVIM_BIN override")
    end
  end

  local zals = require("zals")
  zals.setup({ enabled = false, filetype_detection = false })
  t.equal(package.loaded["zals.filetypes"], nil, "detection can be skipped")
  local config = vim.lsp.config.zals
  t.equal(config.cmd, { "zals", "--stdio" })
  t.equal(config.filetypes, { "yaml.ansible", "jinja2" })
  t.equal(config.root_markers, { ".git" })
  t.equal(config.cmd_env, nil, "do not override collection paths")
  t.equal(config.settings.ansible.python.venvPath, ".venv")
  t.equal(config.settings.ansible.validation.lint.autoFixOnSave, false)

  vim.lsp.config("zals", { cmd = transport })
  t.open(t.root .. "/configuration-only.yml")
  vim.bo.filetype = "yaml.ansible"
  vim.wait(100)
  t.equal(starts, 0, "configuration-only mode must not start a client")

  zals.setup({
    enabled = false,
    filetype_detection = { filename = { ["deploy.yaml"] = "yaml.ansible" } },
    lsp = {
      cmd = { "/custom/zals", "--stdio", "--venv", ".venv-ansible" },
      filetypes = { "yaml.ansible" },
      settings = { ansible = { validation = { enabled = false } } },
    },
  })
  t.equal(vim.lsp.config.zals.cmd, { "/custom/zals", "--stdio", "--venv", ".venv-ansible" })
  t.equal(vim.lsp.config.zals.filetypes, { "yaml.ansible" }, "list overrides replace defaults")
  t.equal(vim.lsp.config.zals.settings.ansible.validation.enabled, false)
  t.equal(vim.lsp.config.zals.settings.ansible.completion.provideModuleOptionAliases, true)
  vim.lsp.config("zals", { cmd = transport })
  t.open(t.root .. "/deploy.yaml", "yaml.ansible")
  vim.wait(100)
  t.equal(starts, 0, "overrides must not implicitly enable the server")

  zals.setup({ lsp = { cmd = transport, filetypes = { "yaml.ansible", "jinja2" } } })
  t.client(t.open(t.root .. "/site.yaml", "yaml.ansible"))

  -- A nearer ansible.cfg must not shrink the Git workspace.
  t.write(t.root .. "/nested/ansible.cfg", { "[defaults]" })
  for _, ext in ipairs({ "yml", "yaml" }) do
    local paths = {
      "requirements." .. ext,
      "execution-environment." .. ext,
      "galaxy." .. ext,
      "site." .. ext,
      "nested/playbooks/deploy." .. ext,
      "roles/web/defaults/main/settings." .. ext,
      "roles/web/vars/main." .. ext,
      "roles/web/tasks/nested/configure." .. ext,
      "ansible_collections/acme/demo/galaxy." .. ext,
      "ansible_collections/acme/demo/roles/web/vars/main." .. ext,
    }
    -- Standalone roles: both metadata extensions, nested variable directories.
    local standalone = t.root .. "/standalone-" .. ext
    t.write(standalone .. "/meta/main." .. ext, { "galaxy_info: {}" })
    for _, dir in ipairs({ "defaults", "vars", "tasks", "handlers", "meta", "templates" }) do
      paths[#paths + 1] = "standalone-" .. ext .. "/" .. dir .. "/nested/main." .. ext
    end
    for _, path in ipairs(paths) do
      local bufnr = t.open(t.root .. "/" .. path, "yaml.ansible")
      local client = t.client(bufnr)
      t.equal(client.config.root_dir, t.root, "Git workspace root")
    end
    local bufnr = t.open(standalone .. "/templates/nested/config.j2", "jinja2")
    t.client(bufnr)
  end
  t.client(t.open(t.root .. "/roles/web/templates/nested/app.conf.j2", "jinja2"))
  t.client(t.open(t.root .. "/ansible_collections/acme/demo/roles/web/templates/app.j2", "jinja2"))
  t.client(t.open(t.root .. "/deploy.yaml", "yaml.ansible"))
  t.equal(starts, 1, "reuse the server in one workspace")

  for _, path in ipairs({
    ".github/workflows/ci.yml",
    "ordinary.yaml",
    "templates/settings.yml",
    "vars/main.yaml",
    "defaults/main.yml",
    "tasks/settings.yml",
    "handlers/main.yaml",
  }) do
    local bufnr = t.open(t.root .. "/" .. path, "yaml")
    vim.wait(50)
    t.equal(#vim.lsp.get_clients({ bufnr = bufnr, name = "zals" }), 0, path .. ": no zals")
  end
  local bufnr = t.open(t.temp .. "/loose/site.yml", "yaml.ansible")
  t.client(bufnr)
  t.equal(starts, 2, "single-file support without a Git root")

  -- Repeating setup must not create duplicate clients.
  zals.setup()
  t.client(bufnr)
  t.equal(starts, 2)

  -- Role name validation and interactive command handlers (zals.extractToRole, :ZalsCreateRole).
  local cmds = require("zals.commands")
  local valid_name, valid_err = cmds.validate_role_name("web_server_1")
  t.equal(valid_name, "web_server_1")
  t.equal(valid_err, nil)
  t.equal((cmds.validate_role_name("")), nil, "empty role name rejected")
  t.equal((cmds.validate_role_name("acme.web.role")), nil, "dotted role name rejected")
  t.equal((cmds.validate_role_name("bad-role")), nil, "hyphenated role name rejected")

  local orig_input, orig_select = vim.ui.input, vim.ui.select
  local next_input, next_select_idx = "webserver", 2
  vim.ui.input = function(_, on_confirm)
    on_confirm(next_input)
  end
  vim.ui.select = function(items, _, on_choice)
    on_choice(items[next_select_idx])
  end

  local active_client = t.client(bufnr)
  executed_commands = {}
  mock_candidates = {
    { dir = t.root .. "/roles", label = "./roles", displayDir = "./roles", collection = vim.NIL },
    {
      dir = t.root .. "/ansible_collections/acme/demo/roles",
      label = "acme.demo (ansible_collections/acme/demo/roles)",
      displayDir = "ansible_collections/acme/demo/roles",
      collection = "acme.demo",
    },
  }

  active_client:exec_cmd({
    title = "Extract task to include_role...",
    command = "zals.extractToRole",
    arguments = {
      {
        uri = vim.uri_from_bufnr(bufnr),
        keyword = "include_role",
        candidates = mock_candidates,
      },
    },
  }, { bufnr = bufnr, client_id = active_client.id })

  assert(vim.wait(1000, function()
    return #executed_commands == 1
  end), "zals.extractToRole should forward workspace/executeCommand after prompting")
  t.equal(executed_commands[1].command, "zals.extractToRole")
  t.equal(executed_commands[1].arguments[1].name, "webserver")
  t.equal(executed_commands[1].arguments[1].targetDir, t.root .. "/ansible_collections/acme/demo/roles")
  t.equal(executed_commands[1].arguments[1].collection, "acme.demo")

  next_input, next_select_idx = "db_role", 1
  executed_commands = {}
  vim.cmd("ZalsCreateRole")
  assert(vim.wait(1000, function()
    return #executed_commands == 2
  end), ":ZalsCreateRole should query candidates then execute zals.createRole")
  t.equal(executed_commands[1].command, "zals.createRole")
  t.equal(executed_commands[1].arguments[1].name, nil)
  t.equal(executed_commands[2].command, "zals.createRole")
  t.equal(executed_commands[2].arguments[1].name, "db_role")
  t.equal(executed_commands[2].arguments[1].targetDir, t.root .. "/roles")
  t.equal(executed_commands[2].arguments[1].collection, nil)

  vim.ui.input, vim.ui.select = orig_input, orig_select
end)
