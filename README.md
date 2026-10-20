# zals.nvim

Neovim configuration for [zals](https://github.com/kksat/zals), the Zig Ansible
Language Server. Uses Neovim's native LSP client; no runtime dependency on
nvim-lspconfig, Mason, or a plugin manager.

- Ansible filetype detection for playbooks, collections, and role YAML, including
  standalone role repositories and nested `defaults/main/` and `vars/main/`.
- Jinja template detection inside roles.
- LSP defaults for completion, hover, diagnostics, symbols, navigation, and code
  actions, plus interactive prompts (`vim.ui.input` and `vim.ui.select`) for
  `:ZalsCreateRole` and `Extract task(s) to include_role...` / `import_role...`.
  Feature implementation lives in the server, not this plugin.

## Requirements

- **Neovim 0.11+**.
- **Git** to install and update the plugin.
- **zals**, installed separately and available to the Neovim process.
- Ansible tools (`ansible`, `ansible-config`, `ansible-doc`, `ansible-playbook`)
  for module documentation, discovery, and validation.
- `ansible-lint` is optional; validation falls back to syntax checking.

The plugin does not download executables, build the server, activate Python
environments, or execute playbooks on its own. Server validation may invoke
Ansible tools. Automatic lint fixes are disabled by default.

## Install the server

Choose one method:

```sh
# Homebrew (macOS and Linux)
brew tap kksat/tap
brew install zals

# Or pip, in the Python environment used to launch Neovim
python3 -m pip install zals
```

Alternatively, download a binary from the
[zals releases](https://github.com/kksat/zals/releases), or build a checkout with
`make build` and use its `zig-out/bin/zals`. Zig is needed only for source builds.
Install `ansible-core` and optionally `ansible-lint` in your chosen Python
environment, and ensure its executable directory is on Neovim's `PATH`.

Verify from the same environment that launches Neovim:

```sh
zals --version
ansible --version
ansible-doc --version
```

For remote Neovim sessions, install the tools on the remote host.

## Install the plugin

### lazy.nvim

Add this spec to your plugin list. lazy.nvim clones `kksat/zals.nvim` from
GitHub and manages updates, just like your other plugins:

```lua
{
  "kksat/zals.nvim",
  main = "zals",
  lazy = false, -- register filetype rules before opening buffers
  opts = {},
}
```

Run `:Lazy sync` and restart Neovim. No local development checkout is needed.
The ZALS server executable is installed separately as described above.

### Native packages (without a plugin manager)

Clone the plugin into Neovim's package directory (default Unix layout):

```sh
git clone https://github.com/kksat/zals.nvim.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/pack/plugins/start/zals.nvim"
```

Add to `init.lua` before opening files:

```lua
vim.cmd.packadd("zals.nvim")
require("zals").setup()
```

Update the package with `git pull --ff-only` from its cloned directory.

## LazyVim

Put the following in `lua/plugins/zals.lua`. This replaces the handwritten ZALS
server configuration; do not keep a second `ansiblels` configuration pointing
at ZALS. The plugin registers filetypes and defaults, and LazyVim enables ZALS
through its `servers` table:

```lua
return {
  {
    "kksat/zals.nvim",
    main = "zals",
    lazy = false,
    opts = { enabled = false }, -- LazyVim enables it below
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        zals = { mason = false }, -- install the binary separately
        ansiblels = { enabled = false },
        yamlls = {
          filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values" },
        },
      },
    },
  },
}
```

For a development binary, add `cmd` under `servers.zals`:

```lua
zals = {
  mason = false,
  cmd = { vim.fn.expand("~/dev/zals/zig-out/bin/zals"), "--stdio" },
},
```

Do not call `mason-lspconfig.setup()` separately before LazyVim configures it:
that can auto-enable installed servers before LazyVim excludes `ansiblels`.
ZALS is installed separately; this plugin does not ask Mason to install it.

## Configuration

`require("zals").setup(opts)` accepts three options:

| Option | Default | Purpose |
| --- | --- | --- |
| `enabled` | `true` | Enable `zals` via `vim.lsp.enable`. With `false`, only register configuration and filetypes; another manager may enable it. Does not stop an existing client. |
| `filetype_detection` | `{}` | Extra `vim.filetype.add` rules, merged with defaults. Set `false` to skip registering rules. |
| `lsp` | `{}` | Native `vim.lsp.config` overrides, deep-merged with the [default configuration](lsp/zals.lua). Lists such as `cmd` and `filetypes` are replaced, not appended. |

For example, without LazyVim:

```lua
require("zals").setup({
  filetype_detection = {
    filename = { ["deploy.yml"] = "yaml.ansible" },
  },
  lsp = {
    cmd = { "/absolute/path/to/zals", "--stdio" },
    settings = {
      ansible = {
        python = { venvPath = ".venv-ansible" },
        validation = { lint = { enabled = false } },
      },
    },
  },
})
```

In LazyVim, use the plugin's `opts.filetype_detection` for detection and
`opts.servers.zals` in the nvim-lspconfig spec for native LSP options such as
`cmd`, `settings`, `capabilities`, and `on_attach`.

### Filetypes

The defaults recognize both `.yml` and `.yaml` for:

- `requirements`, `execution-environment`, `galaxy`, and `site` filenames.
- Files below `playbooks/`, `roles/<name>/`, and
  `ansible_collections/<namespace>/<collection>/`.
- A standalone role's `defaults/`, `vars/`, `tasks/`, `handlers/`, `meta/`, and
  `templates/` directories when the role has `meta/main.yml` or `meta/main.yaml`.
- Role templates ending in `.j2`, including nested template directories, as
  `jinja2` rather than YAML.

Ordinary YAML outside these paths remains YAML. The collection-wide rule is
intentionally broad, like the original configuration; customize it if your
collection contains non-Ansible YAML. Standalone roles without metadata need
an explicit rule. A collection checkout outside `ansible_collections/` can
use the filename and role rules; add rules for any other Ansible directories.
Rules are **Lua patterns**, not shell globs. Do not classify every YAML file
as Ansible in a mixed-purpose repository.

Detection rules take effect when files are opened. Load the plugin eagerly,
remove superseded personal filetype rules, and restart Neovim after migrating.
To change the filetype of an existing buffer: `:set filetype=yaml.ansible`.

### Workspace and collection paths

The default LSP root marker is **`.git`**, including a Git worktree's `.git`
file. This matches the server's Workspace boundary. A nearer `ansible.cfg`
should control Ansible settings, not shrink workspace-wide navigation.

If you deliberately change the boundary, configure both client and server:

```lua
lsp = {
  root_markers = { ".workspace-root" },
  init_options = {
    ansible = { workspace = { rootMarker = ".workspace-root" } },
  },
},
```

Files outside a workspace can still attach, but workspace-wide results need
an appropriate root. Collection and role discovery use the server's
`ANSIBLE_*` environment, `ansible.cfg`, and selected environment. The plugin
does **not** force `ANSIBLE_COLLECTIONS_PATH=.` or silently prefer a personal
checkout. If needed, set `lsp.cmd_env` explicitly.

`ansible.python.venvPath` defaults to `.venv` relative to the Workspace;
`zals --venv <path>` takes precedence. Selecting a venv controls collection
lookup, **not** Python activation or the `ansible-doc` executable. See the
[server's selected-environment guide](https://github.com/kksat/zals/blob/main/docs/selected-venv-collections.md).

### Role creation and extraction

These features require a server advertising `zals.createRole` and
`zals.extractToRole`. The Homebrew 0.1.0 server does not advertise them;
install a role-enabled server build to use them. Other plugin features remain
available with that release.

`zals.nvim` registers `:ZalsCreateRole` (`require("zals").create_role()`) and
client command handlers for `zals.extractToRole` and `zals.createRole`:

- **Unresolved role reference (`roles:`, `include_role`, `import_role`):** use
  `:lua vim.lsp.buf.code_action()` on the role name to create the role in
  `./roles/<name>` or in any Workspace collection's `roles/<name>` directory.
- **Extract task(s) to a role:** select one or more tasks and choose
  `Extract task(s) to include_role...` or `Extract task(s) to import_role...`
  from `:lua vim.lsp.buf.code_action()`. Neovim prompts for the short role name
  (`^[a-z][a-z0-9_]*$`, no dots) and target `roles/` directory (`./roles` or a
  Workspace collection's `roles/` folder).
- **Create a role explicitly:** run `:ZalsCreateRole` in an Ansible buffer to
  prompt for the role name and destination `roles/` folder and open the new
  `tasks/main.yml`.

### Other language servers

Neovim has no general LSP priority setting. Disable `ansiblels` when replacing
it with ZALS, and keep `yamlls` on non-Ansible filetypes. Outside LazyVim:

```lua
vim.lsp.enable("ansiblels", false)
vim.lsp.config("yamlls", {
  filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values" },
})
```

The plugin does not modify other servers. Configure their owner (LazyVim,
Mason, or your own setup) so it does not re-enable conflicting configurations.
Restart after changes; a previously attached `yamlls` may remain attached to
an already-open buffer. Do not stop a shared client serving ordinary YAML.

## Verify and troubleshoot

Open a role's `vars/main.yml` or a playbook:

1. `:set filetype?` should report `yaml.ansible` (`jinja2` for role templates).
2. `:checkhealth vim.lsp` should show `zals` attached. On setups providing it,
   `:LspInfo` is also useful.
3. `:lua print(vim.fn.executable("zals"))` should print `1` when using `PATH`.
4. Check clients with `:lua vim.print(vim.lsp.get_clients({ bufnr = 0 }))`.
5. On a variable key or use, try `:lua vim.lsp.buf.references()` or
   `:lua vim.lsp.buf.definition()`. Results depend on the server's navigation
   scope and index readiness.

If tasks work but variable references do not, check the **source buffer's**
filetype and attached clients first. If workspace results are missing, check
root alignment and collection paths. For server errors, inspect the log at
`:lua print(vim.lsp.get_log_path())`. The
[server's Neovim guide](https://github.com/kksat/zals/blob/main/docs/neovim.md)
has additional details on navigation and filetype detection.

## Development

```sh
make check
make integration ZALS_BIN=/absolute/path/to/zals
make check-all ZALS_BIN=/absolute/path/to/zals
```

`make check-all` runs both suites. `make integrations` is an alias for
`make integration`. Without `ZALS_BIN`, integration uses `zals` from `PATH`.

`make check` checks Lua syntax, default/overridden configuration, filetypes,
and automatic attachment using an in-process LSP transport. It requires only
Neovim and Git, not your personal config or external plugins. CI runs it on
Neovim 0.11.0 and stable.

The integration test uses a real ZALS process to check references from
collection and standalone role variable keys, both YAML extensions, Jinja
attachment, and ordinary YAML exclusion. It also tests role extraction when
the server advertises both role commands. Older servers (including Homebrew
0.1.0) print an explicit `SKIP role integration` after passing navigation
checks. A server that advertises the commands must pass the role assertions;
missing actions and failed edits are never skipped.

To require role integration with **no skips**, select a role-enabled build:

```sh
make integration-roles ZALS_BIN=/absolute/path/to/role-enabled/zals
```

This target fails with a capability error if the selected binary lacks the
commands, rather than silently choosing a personal development checkout.
Neither suite needs Galaxy downloads or playbook execution.
Use `make check NVIM_BIN=/path/to/nvim` to test another
Neovim executable (the same override works for `make integration`). `NVIM_BIN`
is separate from `NVIM`, which Neovim exports as its server socket in terminal
jobs; both targets can be run from a Neovim terminal.

## License

GPL-3.0-only. See [LICENSE](LICENSE) and [source attribution](NOTICE.md).
