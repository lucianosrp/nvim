# CLAUDE.md — Neovim config

Guidance for Claude Code when working in this directory (`~/.config/nvim`).

## Project goals (non-negotiable)

This config exists to be **fast** and **easy to install**. Every change must
preserve both:

1. **Extremely fast startup**, even on large repos.
2. **Dead-simple install** — one self-contained script, no plugin-manager
   framework (no lazy.nvim / packer / Mason), no distro.

If a request conflicts with these goals, say so and propose the lean alternative.

## Files

This repo **is** the Neovim config — it clones directly into `~/.config/nvim`.

- `init.lua` — the entire config, one file, ordered top-to-bottom (leader →
  clipboard → perf → options → diagnostics → plugins → setup/keymaps → venv →
  LSP → hover → autocmds → theme → hot-reload).
- `colors/teal.lua` — house colorscheme (the default). `colors/dank.lua` —
  DankMaterialShell-driven scheme; silently falls back to teal when DMS's
  `lua/plugins/dankcolors.lua` is absent (so the config stays portable).
- `install.sh` — Linux/macOS installer (multi-distro deps + uv/ty/ruff + **git
  clone** the config + compile parsers). `install.ps1` — Windows (winget/scoop).
- `queries/markdown*/injections.scm` — empty overrides; see Gotchas.
- `README.md` — user-facing guide. `.gitignore` — per-machine state
  (`nvim-pack-lock.json`, `lua/plugins/dankcolors.lua`).

## Hard rules

- **The installers pull the live config via `git`** — `init.lua` is NOT embedded
  in any script anymore. Edit `init.lua` directly; it's the single source of
  truth. `install.sh`/`install.ps1` only clone/pull this repo into the nvim dir.
- **Use built-in `vim.pack` only** for plugins. Never introduce a plugin
  manager. Guard `vim.pack.add` (pcall) and gate non-core plugins behind
  discovery/flags (`vim.g.have_nerd_font`, DMS file present) so a missing one
  never aborts startup.
- **Target Neovim ≥ 0.12.** Use modern APIs: `vim.lsp.config`/`vim.lsp.enable`,
  `vim.pack`, `vim.diagnostic.jump`, `vim.uv`, `vim.lsp.completion`. Guard
  `vim.loader` so an odd build can't abort the config.
- **Stay portable.** No hard dependency on the local desktop: clipboard adapts
  (wl-clipboard/native locally, OSC 52 over SSH, native on Windows); themes and
  Python LSPs degrade gracefully when their tools/files are absent.
- **Minimal plugins.** Four core (fzf-lua, treesitter, gitsigns, diffview) +
  opt-in extras (kanagawa, base16 for `dank`, devicons). A new one needs real
  justification against the speed goal; always prefer a built-in.
- **Preserve the look:** transparent UI for any scheme via the `transparent()`
  autocmd on `ColorScheme`; per-theme colors live in `colors/*.lua`.
- **Keymap discipline:** leader = `Space`. Namespaces are taken: `<leader>h*` =
  git hunks, `<leader>g*` = diff/git views. Don't create prefix collisions
  (e.g. a standalone `<leader>h`/`<leader>g`).
- **Guard plugin use** with `pcall(require, ...)` so a missing/uninstalled
  plugin never breaks startup.

## Verifying changes (headless, no UI needed)

```bash
# config loads cleanly?
nvim --headless +qa 2>&1 | grep -iE 'error|E[0-9]+:' || echo OK

# inspect a highlight group / option / keymap
nvim --headless -c 'lua print(vim.inspect(vim.api.nvim_get_hl(0,{name="DiffAdd"})))' -c qa

# LSP attaches on a real file
nvim --headless -c 'edit some.py' \
  -c 'lua vim.wait(8000,function() return #vim.lsp.get_clients({bufnr=0})>0 end)' \
  -c 'lua print(vim.inspect(vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({bufnr=0}))))' -c qa

# startup cost
nvim --startuptime /tmp/st.log +q && tail -1 /tmp/st.log
```

Prefer writing results to a temp file (`vim.fn.writefile`) — headless stdout
interleaves with plugin/parser progress messages.

## Known gotchas

- **Markdown Treesitter crash** (`attempt to call method 'range' (a nil value)`):
  nvim-treesitter `master`'s **bundled** markdown injection query crashes on
  Neovim 0.12 core. `queries/markdown/injections.scm` is an **authoritative**
  override (no `; extends`) carrying only two safe injections — fenced-code-block
  language injection (so ```python` etc. highlight) and inline→markdown_inline.
  `queries/markdown_inline/injections.scm` stays **empty** (its bundled query is
  where the crash actually lives). Don't add `; extends` (re-pulls the crashing
  query) and don't put injections in the markdown_inline file. Revisit if TS
  moves to the `main` branch (ships a compatible query).
- **Diff foreground:** the `default` scheme sets a white `fg` on
  `DiffAdd`/`DiffChange`/`DiffText`, hiding syntax. `style()` overrides them to
  background-only tints. Don't reintroduce a `fg` on those.
- **This machine** (CentOS 8, glibc 2.28): no prebuilt Neovim runs; it was built
  from source to `~/.local` (system `/usr/bin/nvim` is old 0.8). `~/.local/bin`
  must precede `/usr/bin` on PATH. Build via direct `cmake` calls, NOT
  `make CMAKE_INSTALL_PREFIX=...` (that triggers a GNU Make 4.2.1 bug).

## Extending

See README.md "Extending". In short: add to `vim.pack.add{}`; configure with a
`pcall(require,...)` guard; LSPs via `vim.lsp.config` + `vim.lsp.enable`; TS
langs via `ensure_installed`; colors via the `accent` table and `style()`.
