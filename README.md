# zals.nvim

Neovim configuration for [zals](https://github.com/kksat/zals), the Zig Ansible
Language Server. Uses Neovim's native LSP client; no runtime dependency on
nvim-lspconfig, Mason, or a plugin manager.

- Ansible filetype detection for playbooks, collections, and role YAML, including
  standalone role repositories and nested `defaults/main/` and `vars/main/`.
- Jinja template detection inside roles.
- LSP defaults for completion, hover, diagnostics, symbols, navigation, and code
  actions. Feature implementation lives in the server, not this plugin.

## Requirements

- **Neovim 0.11+**.
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

## Install the plugin locally (before publication)

This repository can be used without a GitHub remote. With the checkout at
`~/dev/zals.nvim`, add this lazy.nvim spec:

```lua
{
  dir = vim.fn.expand("~/dev/zals.nvim"),
  name = "zals.nvim",
  main = "zals",
  lazy = false, -- register filetype rules before opening buffers
  opts = {},
}
```

Without a plugin manager, add to `init.lua` before opening files:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand("~/dev/zals.nvim"))
require("zals").setup()
```

After the repository is published as `kksat/zals.nvim`, the lazy.nvim spec can
use `"kksat/zals.nvim"` instead of `dir` and `name`. Keep `main`, `lazy`, and
`opts`. The examples here do not require publication.

## LazyVim

Put the following in `lua/plugins/zals.lua`. This replaces the handwritten ZALS
server configuration; do not keep a second `ansiblels` configuration pointing
at ZALS. The plugin registers filetypes and defaults, and LazyVim enables ZALS
through its `servers` table:

```lua
return {
  {
    dir = vim.fn.expand("~/dev/zals.nvim"),
    name = "zals.nvim",
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
```

`make check` checks Lua syntax, default/overridden configuration, filetypes,
and automatic attachment using an in-process LSP transport. It requires only
Neovim and Git, not your personal config or external plugins. CI runs it on
Neovim 0.11.0 and stable.

The optional integration test uses a real ZALS process to check references
from collection and standalone role variable keys, both YAML extensions,
Jinja attachment, and ordinary YAML exclusion. It needs no Galaxy downloads
or playbook execution. Override `NVIM` to test another Neovim executable.

## License

GPL-3.0-only. See [LICENSE](LICENSE) and [source attribution](NOTICE.md).
