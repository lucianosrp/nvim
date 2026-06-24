# Fast Neovim config

A deliberately small, fast Neovim setup for Python work and quick file/diff
navigation. **Two goals drive every decision:**

1. **Extremely fast** — instant startup even on big repos.
2. **Very easy to install** — one script, no plugin-manager framework, no distro.

It uses Neovim built-ins plus a handful of small plugins, all managed by the
built-in `vim.pack` (Neovim 0.12+). No lazy.nvim, no Mason, no LazyVim.

---

## What's inside

| Area | Tool | Notes |
|------|------|-------|
| Fuzzy find | **fzf-lua** + `fzf`/`ripgrep`/`fd` | files, live grep, symbols, keymaps, colorschemes |
| Python LSP | **ty** (type check) + **ruff** (lint/format) | native `vim.lsp`, no lspconfig |
| Syntax colors | **nvim-treesitter** (`master`) | rich highlighting |
| Git signs | **gitsigns.nvim** | add/change/delete + hunk ops |
| Diff / PR review | **diffview.nvim** | Zed-style review, branch/PR-in-a-worktree |
| Themes | `teal` (house), `dank` (DankMaterialShell-driven), **kanagawa** | transparent over any scheme |
| Icons | **nvim-web-devicons** | optional, gated on a Nerd Font |

The four **core** plugins are fzf-lua, nvim-treesitter, gitsigns, and diffview.
The rest are opt-in extras: `kanagawa` (a theme), `base16-nvim` (engine for the
`dank` scheme), and `nvim-web-devicons` (file icons, only loaded when a Nerd Font
is present).

---

## Requirements

- **Neovim ≥ 0.12** (needs `vim.pack`, native LSP API, `vim.uv`, `vim.base64`)
- `git`, a C compiler (`gcc`) for Treesitter parsers
- `ripgrep`, `fzf` (and optionally `fd`)
- `ty` and `ruff` on `PATH` (installed via `uv tool install`)
- Optional: `wl-clipboard` (Wayland) or `xclip`/`xsel` (X11) for system-clipboard
  copy **and** paste locally; without it, copy still works over SSH via OSC 52
- Optional: a **Nerd Font** in your terminal for file icons

## Install

The installers handle everything: dependencies, `ty`/`ruff` via `uv`, cloning
the config into your nvim dir, and pre-compiling parsers.

**Linux / macOS** — one line:

```bash
curl -fsSL https://raw.githubusercontent.com/lucianosrp/nvim/main/install.sh | bash
```

…or from a clone: `git clone https://github.com/lucianosrp/nvim ~/.config/nvim && ~/.config/nvim/install.sh`

Covers `pacman` (Arch), `apt` (Debian/Ubuntu), `dnf` (Fedora/RHEL), `zypper`
(openSUSE), `apk` (Alpine), `xbps` (Void), and Homebrew (macOS). Where the
distro's Neovim is older than 0.12 (e.g. Debian/Ubuntu), it pulls the official
prebuilt automatically.

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/lucianosrp/nvim/main/install.ps1 | iex
```

Uses `winget` (or `scoop`). Treesitter parser compilation needs a C compiler on
`PATH` (zig or MSVC Build Tools); without one, syntax still works.

**Updating:** re-run the installer, or `git -C ~/.config/nvim pull`. Re-runs are
**fast and idempotent** — system packages use `--needed`, and Treesitter only
compiles parsers that are *missing* (so an update that adds no parsers skips the
slow compile). Re-runs are also safe: the installer **stashes any local edits,
pulls, then re-applies them**
(worst case they're kept in `git stash`). Your **colorscheme also survives
updates**: the active scheme is remembered in the state dir (outside git), so
picking one with `<leader>uc` (or `:colorscheme`) sticks across restarts *and*
upgrades — `git pull` never touches it.

> **Source repo:** the installers clone `lucianosrp/nvim`. Self-hosting a fork?
> Set `NVIM_CONFIG_REPO=<url>` (bash) / `$env:NVIM_CONFIG_REPO` (pwsh).
> On glibc < 2.31 (CentOS/RHEL 8) the prebuilt won't run — build from source.

---

## Keymaps

Leader is **`Space`**. Press **`<leader>k`** anytime for a searchable cheatsheet
of every mapping.

### Files / search
| Key | Action |
|-----|--------|
| `<leader>f` / `Ctrl-p` | Find files |
| `<leader>/` | Live grep |
| `<leader>*` | Grep word under cursor |
| `<leader>b` / `<leader>o` | Buffers / recent files |
| `<leader>q` | Close buffer (keeps the window/split) |
| `<leader>s` / `<leader>S` | Document / workspace symbols |
| `<leader>x` / `<leader>X` | Document / workspace diagnostics |
| `<leader>R` | Resume last picker |
| `<leader>?` | Help tags |
| `<leader>k` | Keymaps cheatsheet |
| `<leader>uc` | Colorschemes (live preview) |
| `<leader>v` | Pick a Python virtualenv |
| `<leader>e` | File explorer (netrw `:Explore`) |
| `<leader>cd` | cd to current file's dir (so pickers follow you) |
| `<leader><Esc>` | Zoom the current window fullscreen / back (toggle) |
| `Ctrl-h/j/k/l` | Move between split windows |

### LSP (in code buffers)
| Key | Action |
|-----|--------|
| `gd` `gD` `gi` `gy` | Definition / declaration / implementation / type-def |
| `gr` | References (fzf) · `K` Hover |
| `<leader>rn` `<leader>ca` `<leader>F` | Rename / code action / format |
| `[d` `]d` `<leader>d` | Prev / next / show line diagnostic |

### Python REPL (inline, ephemeral)
| Key | Action |
|-----|--------|
| `<leader>r` (visual) | Run the selected lines in a live kernel |
| `<leader>rr` | Run the current paragraph — or, in Markdown, the enclosing ```python fence |
| `<leader>rc` | Clear the inline outputs |
| `<leader>rk` | Restart the kernel (fresh state) |

Select Python code and run it in a persistent **ipykernel** living in your
**active venv** — output (stdout, the `Out[n]` result, and tracebacks) renders as
dim **virtual lines under the code**, never written into the buffer. State
persists across runs, so it's a real REPL: define something in one selection,
use it in the next. An output stays put until you **edit the code that produced
it** — adding a line just below it leaves it in place. In a **Markdown** file,
`<leader>rr` runs the ```python` / ```py` fenced block under your cursor. Needs
`ipykernel` in the venv (`uv pip install ipykernel`); if it's missing the keys
just say so. No plugin — a tiny stdio daemon (`python/jrepl.py`) runs in the venv
python and Neovim only renders.

### Markdown
Fenced code blocks are highlighted in their own language (```python`, ```lua`, …)
and folding is on by sections (headers) and code fences — `za`/`zo`/`zc` to
toggle a fold, `zR`/`zM` to open/close all. Files open fully unfolded.

### Git
| Key | Action |
|-----|--------|
| `]h` `[h` | Next / prev hunk |
| `<leader>hp` `<leader>hs` `<leader>hr` | Preview / stage / reset hunk |
| `<leader>hb` `<leader>hd` `<leader>hq` | Blame / diff file / all hunks → quickfix |
| `<leader>gs` | Git status (changed files — fuzzy, with diff preview) |

### Diff & PR review
| Key | Action |
|-----|--------|
| `<leader>gd` | Diff: working changes |
| `<leader>gm` | Diff: branch vs `main` |
| `<leader>gp` | Diff: vs previous commit |
| `<leader>gh` `<leader>gl` | File / repo history |
| `<leader>gc` | Close diffview |
| `<leader>gr` | **Review a branch/PR** in a throwaway worktree (pure git, tokenless) |
| `<leader>gP` | **Forge PR review** — list open PRs (GitHub/Bitbucket) with status, pick one → worktree + panel |
| `<leader>gt` | Toggle the PR panel (description / status / comments / inline comments) |
| `<leader>gi` | Toggle inline PR comments rendered on the diff lines |
| `<leader>gR` | Finish review (remove the worktree) |
| `<leader>gw` | **Worktrees** — list/switch (preview commits + status), `ctrl-n` create, `ctrl-x` remove |

Inside diffview: `<Tab>`/`<S-Tab>` next/prev file, `gf` jump to real file, `g?` help.

**`<leader>gP`** detects the forge from `origin`: GitHub via the `gh` CLI,
Bitbucket via its REST API (set `BITBUCKET_USER` + `BITBUCKET_TOKEN`). The panel
shows the PR **description, status** (draft / merged / approved / CI), **comments**,
and **inline per-line comments**; `<leader>gt` hides/re-shows it. Inline comments
are *also rendered right on the diff* — as virtual lines under the commented line
of the new file (with a `▌` gutter mark), so you read each one in context as you
scroll. `<leader>gi` toggles them off/on.

**`<leader>gw`** maps every worktree of the repo — handy when agents spin up
several and you lose track. Each row shows the current marker, branch, path, a
`clean`/`✗ dirty`/`(PR review)`/`(prunable)` tag and the last commit (subject ·
age), sorted current → dirty → clean; the preview pane shows that worktree's
recent commits and working-tree status. `Enter` jumps in (`tcd` + files picker),
`ctrl-n` creates a new worktree (prompts a branch), `ctrl-x` removes one.

---

## Features

- **Python virtualenv detection.** On opening a `.py` file, the nearest
  `.venv`/`venv`/`env` is found by walking up from the file and exported as
  `VIRTUAL_ENV` before ty/ruff start — so monorepos that share one `.venv` above
  per-package `pyproject.toml` resolve correctly. `<leader>v` switches venv
  (fzf picker). A shell-activated venv always wins.
- **Format on save.** Python buffers are formatted with **ruff** on `:w`
  (skipped for files > 1 MB). `<leader>F` formats manually.
- **PR / branch review in a worktree.** `<leader>gr` fetches a branch, checks it
  out in a **disposable git worktree** (your current checkout is untouched), and
  opens the diff against the base in diffview. `<leader>gR` tears it down. Plain
  `git` only — works with GitHub, Bitbucket, GitLab, anything.
- **Cleaner hover.** `K` decodes HTML entities (`&nbsp;`) and CommonMark
  backslash escapes so docstrings render readably.
- **Smart clipboard.** Locally, Neovim auto-detects `wl-clipboard`/`xclip` for
  full copy *and* paste; over SSH it falls back to OSC 52 (forwarded by the
  terminal), so yanks reach your local clipboard.
- **Hot-reload, including external edits.** Saving `init.lua` *or* having another
  process rewrite it re-sources the config live (libuv `fs_event` watcher) — no
  restart.
- **Minimal statusline** (native, no plugin): relative file path, `[+]`/`[RO]`
  flags, diagnostic counts (only when present), and `line:col`.

---

## Themes

The UI is kept **transparent for any colorscheme** by a `transparent()` autocmd
that strips backgrounds on every `ColorScheme` event — the palette itself comes
from the active scheme. Switch with **`<leader>uc`** (live preview).

| Scheme | Notes |
|--------|-------|
| `teal` *(default)* | the house look — built-in `default` + teal accents (`colors/teal.lua`) |
| `dank` | follows **DankMaterialShell**: loads DMS's generated `lua/plugins/dankcolors.lua` and live-reloads when DMS changes colors (`colors/dank.lua`) |
| `kanagawa` | bundled example theme |

`dank` integration touches nothing DMS owns — it just reads the file DMS already
generates (when `matugenTemplateNeovim` is on) and re-applies on change. Where
DMS isn't running (e.g. a server), it's a static snapshot of the synced palette,
falling back to `teal` if the file is absent.

To change the default, edit the `vim.cmd.colorscheme("teal")` line near the
bottom of `init.lua`.

---

## How it's organized

The repo **is** the config — it clones straight into `~/.config/nvim`:

```
~/.config/nvim/   (this repo)
├── init.lua                     # the entire config (one file, by design)
├── install.sh                   # Linux/macOS installer (deps + clone + parsers)
├── install.ps1                  # Windows installer (winget/scoop)
├── colors/
│   ├── teal.lua                 # house colorscheme (default)
│   └── dank.lua                 # DankMaterialShell-driven scheme (→ teal if no DMS)
├── queries/
│   ├── markdown/injections.scm        # query overrides (see Troubleshooting)
│   └── markdown_inline/injections.scm
├── .gitignore                   # ignores machine state (see below)
└── README.md / CLAUDE.md
```

Two paths are **git-ignored** as per-machine state, not shipped:
`nvim-pack-lock.json` (vim.pack lock) and `lua/plugins/dankcolors.lua` (written
by DankMaterialShell's matugen integration when present).

`init.lua` is intentionally a **single file**, read top to bottom:
leader → clipboard → performance → options → diagnostics → **plugins** →
plugin setup & keymaps → venv → LSP → hover → autocmds → theme → hot-reload.

**Plugins live on disk at** `~/.local/share/nvim/site/pack/core/opt/` — managed
entirely by `vim.pack`. You never edit that directory by hand.

---

## Extending

The config **hot-reloads**: edit `init.lua`, save, and changes apply instantly
(external edits too). Note: files under `colors/` aren't watched — after editing
one, re-apply with `:colorscheme <name>`.

### Add a plugin
1. Add a line to the `plugins` table passed to `vim.pack.add({ ... })`:
   ```lua
   { src = "https://github.com/owner/repo" },
   ```
   (pin a branch/tag with `version = "main"` if needed).
2. Save → `vim.pack` clones it. Then configure it lower down, guarded so a
   missing plugin never breaks startup:
   ```lua
   local ok, plug = pcall(require, "repo")
   if ok then plug.setup({ ... }) end
   ```
3. Keep the speed goal in mind — every plugin must earn its place.

### Add an LSP server
1. Put the server binary on `PATH` (`uv tool install <server>` or your package
   manager).
2. Define and enable it near the existing `ty`/`ruff` block:
   ```lua
   vim.lsp.config("gopls", { cmd = { "gopls" }, filetypes = { "go" },
     root_markers = { "go.mod", ".git" } })
   vim.lsp.enable({ "ty", "ruff", "gopls" })
   ```
   Buffer keymaps (`gd`, `K`, …) attach automatically via the `LspAttach` autocmd.

### Add a Treesitter language
Add it to `ensure_installed` in the `nvim-treesitter` setup. `auto_install` also
grabs any missing parser the first time you open that filetype.

### Add or change a theme
- **Add one:** add the theme plugin to the `plugins` table, then pick it with
  `<leader>uc`. It'll show its own colors, transparent.
- **A custom scheme:** drop a `colors/<name>.lua` file (see `colors/teal.lua` —
  start with `highlight clear` + `syntax reset` so it round-trips cleanly).
- **Transparency** applies to every scheme via the `transparent()` autocmd;
  don't put per-theme accents there.

### Add keymaps
Use `map(...)` (global) or `bmap(...)` inside `LspAttach` (buffer-local).
**Avoid prefix collisions** — taken namespaces: `<leader>h*` git hunks,
`<leader>g*` diff/git/PR, `<leader>u*` UI/colorschemes.

### Override a Treesitter query
Drop a `.scm` file under `queries/<lang>/<name>.scm`. Files here take precedence
over plugin queries (and fully replace them unless they start with `; extends`).

---

## Updating & removing plugins
```vim
:lua vim.pack.update()          " update all plugins
:lua vim.pack.del({ "name" })   " remove one (also delete its line in `plugins`)
```

## Performance principles (keep these to stay fast)
- One file, lazy where possible; plugins do heavy work only when invoked.
- `vim.loader.enable()` (bytecode cache) stays first.
- Language-host providers and unused builtin plugins are disabled — leave them off.
- The big-file guard strips expensive features above 1 MB.
- Profile startup with `nvim --startuptime /tmp/st.log` before/after a change.

## Troubleshooting
- **Markdown error `attempt to call method 'range'`** — already fixed by the
  empty `queries/markdown*/injections.scm` overrides (nvim-treesitter `master`
  vs Neovim 0.12 incompatibility). Don't delete them unless you move TS to `main`.
- **`<leader>f` searches the wrong folder** — Neovim's cwd is fixed at launch;
  `<leader>cd` re-points it to the current file's directory.
- **A plugin didn't load** — `:lua vim.pack.update()`, then restart.
- **Health check** — `:checkhealth vim.lsp` / `:checkhealth nvim-treesitter`.

## License

[MIT](LICENSE) © Luciano Scarpulla
