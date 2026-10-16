local t = dofile("tests/helpers.lua")
local binary = vim.env.ZALS_BIN or "zals"
assert(vim.fn.executable(binary) == 1, "Set ZALS_BIN to an executable zals binary")

t.run(function()
  local ready = {}
  require("zals").setup({
    lsp = {
      cmd = { binary, "--stdio" },
      init_options = {
        ansible = { validation = { enabled = false, lint = { enabled = false } } },
      },
      settings = {
        ansible = { validation = { enabled = false, lint = { enabled = false } } },
      },
      handlers = {
        ["ansible/workspaceIndexReady"] = function(_, _, ctx)
          ready[ctx.client_id] = true
        end,
      },
    },
  })

  -- Prepare every file before opening a buffer: the initial index must see
  -- all fixtures, independently of platform-specific file watching.
  local cases = {}
  for _, ext in ipairs({ "yml", "yaml" }) do
    for _, role in ipairs({
      t.root .. "/collection-" .. ext .. "/ansible_collections/acme/demo/roles/web",
      t.root .. "/standalone-" .. ext,
    }) do
      t.write(role .. "/meta/main." .. ext, { "galaxy_info: {}" })
      local vars = role .. "/vars/main/settings." .. ext
      local tasks = role .. "/tasks/nested/configure." .. ext
      local template = role .. "/templates/nested/app.j2"
      -- Unique name per Role avoids depending on cross-Role variable scoping.
      local variable = "web_" .. ext .. "_" .. (role:find("/ansible_collections/") and "collection" or "standalone")
      t.write(vars, { variable .. ": value" })
      t.write(tasks, { "- name: Read variable", '  ansible.builtin.debug:', '    msg: "{{ ' .. variable .. ' }}"' })
      t.write(template, { "setting={{ " .. variable .. " }}" })

      cases[#cases + 1] = { vars = vars, tasks = tasks, template = template }
    end
  end

  for _, case in ipairs(cases) do
    vim.cmd.edit(vim.fn.fnameescape(case.vars))
    t.equal(vim.bo.filetype, "yaml.ansible")
    local bufnr = vim.api.nvim_get_current_buf()
    local client = t.client(bufnr)
    assert(vim.wait(10000, function()
      client:request_sync("workspace/symbol", { query = "__wait__" }, 1000, bufnr)
      return ready[client.id]
    end), "Workspace index did not become ready")

    local response, err = client:request_sync("textDocument/references", {
      textDocument = { uri = vim.uri_from_fname(case.vars) },
      position = { line = 0, character = 2 },
      context = { includeDeclaration = false },
    }, 10000, bufnr)
    assert(response and not response.err, vim.inspect(err or response))
    local found = {}
    for _, location in ipairs(response.result or {}) do
      found[location.uri] = true
    end
    t.equal(found[vim.uri_from_fname(case.tasks)], true, "task reference from vars key")
    t.equal(found[vim.uri_from_fname(case.template)], true, "template reference from vars key")

    vim.cmd.edit(vim.fn.fnameescape(case.template))
    t.equal(vim.bo.filetype, "jinja2")
    t.client(vim.api.nvim_get_current_buf())
  end

  local bufnr = t.open(t.root .. "/ordinary.yml", "yaml")
  vim.wait(100)
  t.equal(#vim.lsp.get_clients({ bufnr = bufnr, name = "zals" }), 0)
end)
