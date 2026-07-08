-- ============================================================================
-- Minimal, fast Neovim config
--   * fuzzy file finding (fzf-lua + fzf/ripgrep)
--   * native Python LSP: ty (type-checking) + ruff (lint/format)
--   * gd / references / hover, fast startup on big projects
-- Requires Neovim 0.12+ (vim.pack, vim.lsp.config / vim.lsp.enable).
-- No plugin-manager framework: the single plugin is managed by built-in vim.pack.
-- ============================================================================

-- Hard floor: everything below assumes Neovim >= 0.12 (vim.pack, vim.uv,
-- vim.lsp.enable, completeopt=fuzzy, ...). On an older nvim — typically a stale
-- distro /usr/bin/nvim shadowing the real one on PATH — loading this file would
-- die mid-chunk with a cryptic E5113 and leave the editor half-configured.
-- Bail out early with one clear message instead. Only 0.8-safe APIs here.
if vim.fn.has("nvim-0.12") == 0 then
  vim.schedule(function()
    local v = vim.version()
    vim.notify(
      ("This config needs Neovim >= 0.12; this is %d.%d.%d (%s).\n"
        .. "An old system nvim is probably shadowing the right one on PATH — check `which nvim`.")
        :format(v.major, v.minor, v.patch, vim.v.progpath),
      vim.log.levels.ERROR
    )
  end)
  return
end

-- Enable the Lua module bytecode cache FIRST — biggest single startup win.
-- Guarded: an old/odd nvim build without vim.loader must not abort the whole config.
if vim.loader then vim.loader.enable() end

-- Leader must be set before any plugin/keymap that uses <leader>.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- One augroup for all our autocmds. clear = true wipes it on every (re)source,
-- so hot-reloading init.lua never stacks duplicate autocmds.
local aug = vim.api.nvim_create_augroup("user_config", { clear = true })

-- ---------------------------------------------------------------------------
-- Clipboard: locally (desktop) use the system clipboard via Neovim's built-in
-- auto-detection (wl-clipboard / xclip / xsel) — that gives working copy AND
-- paste. Over SSH (no local clipboard tool), fall back to OSC 52, which the
-- terminal (Ghostty + Zellij) forwards to the local machine. OSC 52 is
-- write-only, so it is the fallback, never the local default.
-- ---------------------------------------------------------------------------
vim.o.clipboard = "unnamedplus"

local has_display = vim.env.WAYLAND_DISPLAY or vim.env.DISPLAY
local is_remote = vim.env.SSH_TTY or vim.env.SSH_CONNECTION
local is_windows = vim.fn.has("win32") == 1 -- Windows: let Neovim use its native clipboard

if not is_windows and (is_remote or not has_display) then
  local function osc52_copy(lines)
    local text = type(lines) == "table" and table.concat(lines, "\n") or lines
    io.stderr:write("\x1b]52;c;" .. vim.base64.encode(text) .. "\x1b\\")
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52_copy, ["*"] = osc52_copy },
    paste = {
      ["+"] = function() return { vim.fn.getreg(""), vim.fn.getregtype("") } end,
      ["*"] = function() return { vim.fn.getreg(""), vim.fn.getregtype("") } end,
    },
  }
end
-- else: leave vim.g.clipboard unset so Neovim auto-detects the native tool.

-- ---------------------------------------------------------------------------
-- Startup performance: skip language-host providers and unused builtin plugins.
-- ---------------------------------------------------------------------------
for _, p in ipairs({ "python3", "ruby", "perl", "node" }) do
  vim.g["loaded_" .. p .. "_provider"] = 0
end
for _, p in ipairs({
  "gzip", "zip", "zipPlugin", "tar", "tarPlugin",
  "getscript", "getscriptPlugin", "vimball", "vimballPlugin",
  "2html_plugin", "tutor_mode_plugin", "rplugin", "spellfile_plugin",
}) do
  vim.g["loaded_" .. p] = 1
end

-- ---------------------------------------------------------------------------
-- Editor options
-- ---------------------------------------------------------------------------
local o = vim.opt
o.number = true
o.relativenumber = true
o.signcolumn = "yes"            -- no layout shift when diagnostics appear
o.cursorline = true
o.termguicolors = true
o.mouse = "a"
o.scrolloff = 6
o.sidescrolloff = 8
o.wrap = false
o.splitright = true
o.splitbelow = true
o.ignorecase = true
o.smartcase = true
o.undofile = true               -- persistent undo
o.swapfile = false
o.updatetime = 250
o.timeoutlen = 400
o.pumheight = 12
o.completeopt = "menuone,noselect,fuzzy"
o.expandtab = true
o.shiftwidth = 4
o.tabstop = 4
o.smartindent = true
o.synmaxcol = 300               -- stop syntax highlighting past col 300 (long-line lag guard)
o.ttimeoutlen = 10              -- snappy key-code / <Esc> resolution (not the mapping timeout)
o.winborder = "rounded"         -- a thin frame on every float: K hover, signature, rename, etc.

-- ---------------------------------------------------------------------------
-- Diagnostics presentation
-- ---------------------------------------------------------------------------
vim.diagnostic.config({
  severity_sort = true,
  update_in_insert = false,
  virtual_text = { spacing = 2, prefix = "●" },
  float = { border = "rounded", source = true },
  signs = true,
})

-- ---------------------------------------------------------------------------
-- Minimal statusline (native, no plugin): relative path + modified/RO flags,
-- diagnostics counts (only when present), and line:col. Evaluated by `%!` so
-- it updates live. Kept deliberately small.
-- ---------------------------------------------------------------------------
function _G.statusline()
  local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  if rel == "" then rel = "[No Name]" end
  local flags = ""
  if vim.bo.modified then flags = flags .. " [+]" end
  if vim.bo.readonly or not vim.bo.modifiable then flags = flags .. " [RO]" end
  local d = vim.diagnostic.count(0)
  local diag = ""
  if (d[vim.diagnostic.severity.ERROR] or 0) > 0 then diag = diag .. " E" .. d[vim.diagnostic.severity.ERROR] end
  if (d[vim.diagnostic.severity.WARN] or 0) > 0 then diag = diag .. " W" .. d[vim.diagnostic.severity.WARN] end
  -- %< truncate-from-here, %= left/right split, %l:%c line:col
  return "%<" .. rel .. flags .. "%=" .. _G.venv_segment() .. diag .. "  %l:%c "
end

-- Right-side venv / language indicator. Cheap: reads $VIRTUAL_ENV + filetype, no
-- filesystem walk (the statusline re-evaluates constantly). Nerd-Font icons for
-- Python/Rust when available, else a short text tag.
function _G.venv_segment()
  local ft = vim.bo.filetype
  local nf = vim.g.have_nerd_font
  if ft == "python" then
    local v, name = vim.env.VIRTUAL_ENV, "no venv"
    if v and v ~= "" then
      name = vim.fs.basename(v)
      if name == ".venv" or name == "venv" or name == "env" then name = vim.fs.basename(vim.fs.dirname(v)) end
    end
    return (nf and "\u{e73c} " or "py:") .. name .. "  " -- nf-dev-python (snake)
  elseif ft == "rust" then
    return (nf and "\u{e7a8} " or "rs:") .. "rust  " -- nf-dev-rust
  end
  return ""
end
vim.o.statusline = "%!v:lua.statusline()"

-- ---------------------------------------------------------------------------
-- Plugins (built-in package manager — no lazy.nvim / no distro)
-- ---------------------------------------------------------------------------
-- Set false if your terminal lacks a Nerd Font: skips devicons + file icons
-- (glyphs would otherwise render as tofu boxes). Neovim can't detect the
-- terminal font at runtime, so this is a manual switch.
vim.g.have_nerd_font = true

local plugins = {
  { src = "https://github.com/ibhagwan/fzf-lua" },
  -- pinned to master (stable classic API); gives rich syntax colors via Treesitter
  { src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "master" },
  -- git change highlights in the sign column (added / changed / removed lines)
  { src = "https://github.com/lewis6991/gitsigns.nvim" },
  -- Zed-style diff review: panel of changed files + diff, jump to file (gf)
  { src = "https://github.com/sindrets/diffview.nvim" },

  -- Kanagawa theme --
  { src = "https://github.com/rebelot/kanagawa.nvim" },
}
-- DankMaterialShell/matugen integration needs no plugin: colors/dank.lua reads
-- the generated Material palette (colors.json) directly and falls back to teal
-- when it's absent — the config stays fully agnostic with zero extra deps.
-- File-type icons (fzf-lua pickers etc.) — only meaningful with a Nerd Font.
if vim.g.have_nerd_font then
  table.insert(plugins, { src = "https://github.com/nvim-tree/nvim-web-devicons" })
end
-- Guard the install: if one plugin is in a bad state (e.g. an orphaned clone
-- vim.pack lost track of), don't let it abort the whole config and leave the UI
-- half-loaded (no theme/transparency). Plugin *use* is pcall-guarded below too.
local pack_ok, pack_err = pcall(vim.pack.add, plugins)
if not pack_ok then
  vim.notify(
    "vim.pack.add failed: " .. tostring(pack_err) .. "\nSome plugins may be unavailable.",
    vim.log.levels.ERROR
  )
end

-- Treesitter — many more highlight groups => more color (esp. Python).
local ok_ts, tsconfigs = pcall(require, "nvim-treesitter.configs")
if ok_ts then
  tsconfigs.setup({
    ensure_installed = {
      "python", "lua", "vim", "vimdoc", "bash",
      "json", "yaml", "toml", "markdown", "markdown_inline",
    },
    -- note: `rust` is intentionally NOT pre-installed — auto_install compiles it
    -- on demand the first time you open a .rs file, so Rust stays fully optional
    auto_install = true,           -- compile a missing parser on first open (uses gcc)
    highlight = {
      enable = true,
      -- skip Treesitter on big files (ties into the >1 MB guard below) — parsing
      -- a multi-MB file is the real runtime cost, not startup
      disable = function(_, buf) return vim.b[buf].large_file end,
    },
    indent = { enable = true },
  })
end

-- Markdown: Treesitter-powered folding on sections (headers) and fenced code
-- blocks. Opens fully unfolded (high foldlevel) so nothing is hidden on load;
-- za/zc/zo to toggle, zR/zM to open/close all. Skipped on big files (the >1 MB
-- guard sets foldmethod=manual). Code-fence language highlighting comes from the
-- minimal queries/markdown/injections.scm override (the bundled query crashes 0.12).
vim.api.nvim_create_autocmd("FileType", {
  group = aug,
  pattern = "markdown",
  callback = function(args)
    if vim.b[args.buf].large_file then return end
    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
    vim.opt_local.foldlevel = 99
  end,
})

-- File-type icons for fzf-lua pickers (guarded by the Nerd Font flag above).
if vim.g.have_nerd_font then
  pcall(function() require("nvim-web-devicons").setup() end)
end

local map = vim.keymap.set

-- fzf-lua, loaded lazily: require + setup on first use so it costs nothing at
-- startup (it's only needed when you actually open a picker). _fzf: nil = not
-- tried, false = unavailable, table = loaded.
local _fzf
local function load_fzf()
  if _fzf == nil then
    local ok, f = pcall(require, "fzf-lua")
    if not ok then
      vim.notify("fzf-lua not available — run :lua vim.pack.update()", vim.log.levels.WARN)
      _fzf = false
      return nil
    end
    f.setup({
      defaults = { file_icons = vim.g.have_nerd_font and true or false },
      winopts = { height = 0.88, width = 0.88, preview = { default = "builtin" } },
      files = { rg_opts = "--color=never --files --hidden --follow -g '!.git/'" },
    })
    _fzf = f
  end
  return _fzf or nil
end
local function fzf_cmd(method)
  return function()
    local f = load_fzf()
    if f then f[method]() end
  end
end
map("n", "<leader>f", fzf_cmd("files"), { desc = "Find files" })
map("n", "<C-p>", fzf_cmd("files"), { desc = "Find files" })
map("n", "<leader>/", fzf_cmd("live_grep"), { desc = "Live grep" })
map("n", "<leader>*", fzf_cmd("grep_cword"), { desc = "Grep word under cursor" })
map("n", "<leader>b", fzf_cmd("buffers"), { desc = "Buffers" })
map("n", "<leader>o", fzf_cmd("oldfiles"), { desc = "Recent files" })
map("n", "<leader>R", fzf_cmd("resume"), { desc = "Resume last picker" })
map("n", "<leader>s", fzf_cmd("lsp_document_symbols"), { desc = "Document symbols" })
map("n", "<leader>S", fzf_cmd("lsp_live_workspace_symbols"), { desc = "Workspace symbols" })
map("n", "<leader>x", fzf_cmd("diagnostics_document"), { desc = "Document diagnostics" })
map("n", "<leader>X", fzf_cmd("diagnostics_workspace"), { desc = "Workspace diagnostics" })
map("n", "<leader>gs", function()
  local f = load_fzf()
  if not f then return end
  local root = vim.fs.root(0, ".git") -- run git from the buffer's repo, not nvim's cwd
  if not root then
    vim.notify("Not in a git repository", vim.log.levels.WARN)
    return
  end
  f.git_status({ cwd = root })
end, { desc = "Git status (changed files)" })
map("n", "<leader>?", fzf_cmd("helptags"), { desc = "Help tags" })
map("n", "<leader>k", fzf_cmd("keymaps"), { desc = "Keymaps cheatsheet" })
-- Colorscheme picker. `base16-*` stays filtered out: machines that installed
-- the old base16-nvim engine (pre-plugin-free `dank`) may still have its ~100
-- schemes on disk, and they error without the module. Keeps the live preview.
map("n", "<leader>uc", function()
  local f = load_fzf()
  if f then f.colorschemes({ ignore_patterns = { "^base16" } }) end
end, { desc = "Colorschemes" })

-- Gitsigns — added / changed / removed line markers + hunk navigation.
local ok_gs, gitsigns = pcall(require, "gitsigns")
if ok_gs then
  gitsigns.setup({
    signs = {
      add          = { text = "▎" },
      change       = { text = "▎" },
      delete       = { text = "_" },
      topdelete    = { text = "‾" },
      changedelete = { text = "~" },
      untracked    = { text = "▎" },
    },
    signcolumn = true,
    current_line_blame = false,
  })
  map("n", "]h", function() gitsigns.nav_hunk("next") end, { desc = "Next git hunk" })
  map("n", "[h", function() gitsigns.nav_hunk("prev") end, { desc = "Prev git hunk" })
  map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "Preview hunk" })
  map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "Stage hunk" })
  map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "Reset hunk" })
  map("n", "<leader>hb", function() gitsigns.blame_line({ full = true }) end, { desc = "Blame line" })
  map("n", "<leader>hd", gitsigns.diffthis, { desc = "Diff this file" })
  -- quick jump-list of every changed hunk in the repo (lighter than diffview)
  map("n", "<leader>hq", function() gitsigns.setqflist("all") end, { desc = "All hunks -> quickfix" })
end

-- Diffview — Zed-style "review everything that changed, then jump to file".
-- Loaded lazily: require + setup on first use (packadd registers its commands),
-- so it adds nothing to startup. _dv: nil = not tried, false = unavailable.
local _dv
local function load_diffview()
  if _dv == nil then
    pcall(vim.cmd, "packadd diffview.nvim")
    local ok, d = pcall(require, "diffview")
    if ok then
      d.setup({ enhanced_diff_hl = true })
      _dv = d
    else
      _dv = false
    end
  end
  return _dv or nil
end
local function dv_cmd(cmd)
  return function()
    if load_diffview() then vim.cmd(cmd) end
  end
end
-- working tree + staged changes vs HEAD (what an agent just changed, pre-commit)
map("n", "<leader>gd", dv_cmd("DiffviewOpen"), { desc = "Diff: working changes" })
-- the whole branch vs main (a committed cloud-agent session) — edit 'main' if your base differs
map("n", "<leader>gm", dv_cmd("DiffviewOpen main...HEAD"), { desc = "Diff: branch vs main" })
-- against the previous commit only
map("n", "<leader>gp", dv_cmd("DiffviewOpen HEAD~1"), { desc = "Diff: vs previous commit" })
-- change history (current file / whole repo)
map("n", "<leader>gh", dv_cmd("DiffviewFileHistory %"), { desc = "Diff: this file history" })
map("n", "<leader>gl", dv_cmd("DiffviewFileHistory"), { desc = "Diff: repo history" })
map("n", "<leader>gc", dv_cmd("DiffviewClose"), { desc = "Diff: close" })

-- Review a PR/branch (host-agnostic — GitHub, Bitbucket, …) WITHOUT touching
-- your current checkout: fetch the branch into a throwaway git worktree and
-- diff it against base in diffview. <leader>gR tears the worktree down again.
-- Plain git only — no gh/forge CLI. _G state survives config hot-reload.
local function cleanup_review()
  pcall(vim.cmd, "DiffviewClose")
  local r = _G.__pr_review
  if not r then return end
  _G.__pr_review = nil
  _G.__pr_inline = nil -- drop annotations (the worktree buffers are wiped below)
  -- wipe buffers living inside the worktree (they'd dangle once it's gone)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local n = vim.api.nvim_buf_get_name(b)
    if n ~= "" and n:sub(1, #r.wt) == r.wt then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  pcall(vim.cmd.tcd, r.prev) -- leave the worktree dir before deleting it
  local rm = vim.system({ "git", "-C", r.root, "worktree", "remove", "--force", r.wt }, { text = true }):wait()
  vim.system({ "git", "-C", r.root, "worktree", "prune" }, { text = true }):wait()
  vim.notify(
    rm.code == 0 and "Review worktree removed" or ("worktree remove failed:\n" .. (rm.stderr or "")),
    rm.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
  )
end

local function git_root_of(buf)
  local file = vim.api.nvim_buf_get_name(buf or 0)
  local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  local r = vim.trim((vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait().stdout) or "")
  return r ~= "" and r or nil
end

-- Core: fetch a branch into a throwaway worktree + open diffview vs base.
-- Shared by <leader>gr (prompted) and <leader>gP (PR picker). Returns ok.
local function open_review(root, branch, base)
  local function run(c) return vim.system(c, { cwd = root, text = true }):wait() end
  vim.notify("Fetching " .. branch .. " …", vim.log.levels.INFO)
  -- Fetch branch + base, writing real remote-tracking refs. A bare
  -- `git fetch origin <branch>` only updates FETCH_HEAD, so origin/<branch>
  -- won't exist for a freshly-pushed branch and the worktree add (+ merge-base)
  -- below would fail with "invalid reference". Explicit refspecs fix that;
  -- --force in case a tracking ref needs to rewind (force-pushed branch).
  local fr = run({ "git", "fetch", "--force", "origin",
    branch .. ":refs/remotes/origin/" .. branch,
    base .. ":refs/remotes/origin/" .. base })
  if fr.code ~= 0 then
    vim.notify("git fetch failed:\n" .. (fr.stderr or ""), vim.log.levels.ERROR)
    return false
  end
  cleanup_review() -- tear down any previous review
  local wt = vim.fs.joinpath(vim.fn.stdpath("cache"), "pr-review",
    vim.fs.basename(root), (branch:gsub("[^%w._-]", "-")))
  vim.fn.mkdir(vim.fs.dirname(wt), "p")
  vim.system({ "git", "-C", root, "worktree", "remove", "--force", wt }, { text = true }):wait()
  if run({ "git", "worktree", "add", "--detach", wt, "origin/" .. branch }).code ~= 0 then
    vim.notify("git worktree add failed", vim.log.levels.ERROR)
    return false
  end
  _G.__pr_review = { wt = wt, root = root, prev = vim.fn.getcwd() }
  vim.cmd.tcd(wt) -- review inside the worktree; diffview targets it
  -- Diff merge-base(base, branch) vs the worktree's working tree. The worktree
  -- is detached at origin/branch (clean), so this equals the 3-dot PR diff — but
  -- the RIGHT pane is now the real on-disk file (not a diffview:// buffer), which
  -- is what lets inline comments anchor to the right buffer + new-file line.
  local mb = vim.trim((vim.system({ "git", "-C", root, "merge-base",
    "origin/" .. base, "origin/" .. branch }, { text = true }):wait().stdout) or "")
  if load_diffview() then
    vim.cmd("DiffviewOpen " .. (mb ~= "" and mb or ("origin/" .. base .. "...HEAD")))
  end
  return true
end

local function review_branch()
  local root = git_root_of(0)
  if not root then
    vim.notify("Not inside a git repo", vim.log.levels.ERROR)
    return
  end
  local branch = vim.trim(vim.fn.input("Review branch: "))
  if branch == "" then return end
  -- base = remote's authoritative default (local origin/HEAD can be stale)
  local lsr = vim.system({ "git", "-C", root, "ls-remote", "--symref", "origin", "HEAD" }, { text = true }):wait()
  local guess = (lsr.stdout or ""):match("ref:%s+refs/heads/(%S+)") or "main"
  local base = vim.trim(vim.fn.input("Base branch: ", guess))
  if base == "" then return end
  if open_review(root, branch, base) then
    vim.notify(branch .. " vs " .. base .. " (worktree) — <leader>gR when done", vim.log.levels.INFO)
  end
end

-- ---------------------------------------------------------------------------
-- <leader>gP — forge-aware PR review. Detects GitHub (gh) or Bitbucket (REST
-- API via BITBUCKET_USER + BITBUCKET_TOKEN) from origin, lists open PRs with
-- status, and on pick opens the PR branch in a worktree (open_review) plus a
-- floating panel: description, status, comments, and inline per-line comments.
-- A few calls each: list (1), then detail+comments on the chosen PR.
-- ---------------------------------------------------------------------------
local function sysjson(cmd, cwd)
  local ok, r = pcall(function() return vim.system(cmd, { text = true, cwd = cwd }):wait() end)
  if not ok or r.code ~= 0 then return nil end
  local jok, data = pcall(vim.json.decode, r.stdout or "")
  return jok and data or nil
end

local function forge_of(root)
  local url = vim.trim((vim.system({ "git", "-C", root, "remote", "get-url", "origin" }, { text = true }):wait().stdout) or "")
  if url:find("github.com", 1, true) then return "github" end
  if url:find("bitbucket.org", 1, true) then
    local ws, repo = url:match("bitbucket%.org[:/]([^/]+)/([^/%.]+)")
    return "bitbucket", ws or vim.env.BITBUCKET_WORKSPACE, repo or vim.env.BITBUCKET_REPO
  end
end

-- CI rollup → one glyph from a list of check/status objects
local function rollup(checks)
  local fail, pend, ok = false, false, false
  for _, c in ipairs(checks or {}) do
    local s = (c.conclusion or c.state or c.status or ""):upper()
    if s:find("FAIL") or s == "ERROR" then fail = true
    elseif s:find("SUCCESS") or s == "COMPLETED" then ok = true -- SUCCESS (gh) / SUCCESSFUL (bitbucket)
    elseif s ~= "" then pend = true end
  end
  return fail and "✗CI" or (pend and "●CI") or (ok and "✓CI") or "—"
end

-- right-side floating panel (read-only markdown; q closes). The last panel's
-- content is kept in _G so <leader>gt can re-open it after closing without a
-- refetch. Called with `lines` to set new content, or nil to re-show the last.
local function pr_panel(lines)
  if lines then _G.__pr_panel_lines = lines end
  lines = _G.__pr_panel_lines
  if not lines then return end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  local w = math.min(84, math.floor(vim.o.columns * 0.5))
  local h = math.floor(vim.o.lines * 0.85)
  _G.__pr_panel_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h, col = vim.o.columns - w - 1, row = 1,
    style = "minimal", border = "rounded", title = " PR ", title_pos = "center",
  })
  vim.wo[_G.__pr_panel_win].wrap = true
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

-- toggle the PR panel: hide if open, re-show the last PR's panel if closed
local function toggle_pr_panel()
  local w = _G.__pr_panel_win
  if w and vim.api.nvim_win_is_valid(w) then
    vim.api.nvim_win_close(w, true)
    _G.__pr_panel_win = nil
  elseif _G.__pr_panel_lines then
    pr_panel(nil)
  else
    vim.notify("No PR panel yet — open a PR with <leader>gP", vim.log.levels.INFO)
  end
end

local function body_or_none(s)
  return (s and s ~= "") and s or "_(none)_"
end

-- Inline (per-line) comments. Fetchers return a flat list of
--   { path, line, new_line, who, body }
-- where `line` is for the panel listing and `new_line` is the RIGHT-side
-- (new-file) line used to anchor the annotation on the diff — nil when the
-- comment sits on a removed line (those stay in the panel only).
local function inline_section(L, inline)
  if not (inline and #inline > 0) then return end
  L[#L + 1] = ""
  L[#L + 1] = "## Inline comments"
  for _, c in ipairs(inline) do
    L[#L + 1] = ("`%s:%s` **%s:**"):format(c.path or "?", tostring(c.line or "?"), c.who)
    for _, ln in ipairs(vim.split(c.body, "\n")) do L[#L + 1] = "> " .. ln end
  end
end

-- Render inline comments ON the diff: virtual lines (+ a gutter sign) under the
-- commented line of diffview's RIGHT pane (the real worktree file). Annotation
-- state lives in _G so it survives config hot-reload; cleanup_review clears it.
local pr_inline_ns = vim.api.nvim_create_namespace("pr_inline_comments")

local function annotate_buf(buf)
  local r, by_path = _G.__pr_review, _G.__pr_inline
  if not (r and by_path) or _G.__pr_inline_hidden then return end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local name = vim.api.nvim_buf_get_name(buf)
  -- only the real worktree files (right/new pane); skip diffview:// & others
  if name == "" or name:sub(1, #r.wt + 1) ~= (r.wt .. "/") then return end
  local cs = by_path[name:sub(#r.wt + 2)]
  if not cs then return end
  vim.api.nvim_buf_clear_namespace(buf, pr_inline_ns, 0, -1)
  local n = vim.api.nvim_buf_line_count(buf)
  for _, c in ipairs(cs) do
    local vlines = { { { "  💬 " .. c.who, "DiagnosticInfo" } } }
    for _, ln in ipairs(vim.split(c.body, "\n")) do
      vlines[#vlines + 1] = { { "  " .. ln, "Comment" } }
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, pr_inline_ns, math.max(0, math.min(c.line, n) - 1), 0, {
      virt_lines = vlines, sign_text = "▌", sign_hl_group = "DiagnosticInfo",
    })
  end
end

local function place_inline(inline)
  local by_path = {}
  for _, c in ipairs(inline or {}) do
    if c.path and c.new_line then
      by_path[c.path] = by_path[c.path] or {}
      table.insert(by_path[c.path], { line = c.new_line, who = c.who, body = c.body })
    end
  end
  _G.__pr_inline = next(by_path) and by_path or nil
  _G.__pr_inline_hidden = false
  for _, b in ipairs(vim.api.nvim_list_bufs()) do annotate_buf(b) end
end

-- diffview opens each file's diff buffer lazily as you navigate its file panel;
-- re-annotate whenever a buffer is shown. Cheap: annotate_buf bails immediately
-- unless a review is active and the buffer is a worktree file with comments.
vim.api.nvim_create_autocmd({ "BufWinEnter", "BufReadPost" }, {
  group = vim.api.nvim_create_augroup("pr-inline-comments", { clear = true }),
  callback = function(ev) annotate_buf(ev.buf) end,
})

local function toggle_inline()
  if not _G.__pr_inline then
    vim.notify("No inline comments — open a PR with <leader>gP", vim.log.levels.INFO)
    return
  end
  _G.__pr_inline_hidden = not _G.__pr_inline_hidden
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if _G.__pr_inline_hidden then
      pcall(vim.api.nvim_buf_clear_namespace, b, pr_inline_ns, 0, -1)
    else
      annotate_buf(b)
    end
  end
end

-- GitHub (gh)
local function gh_prs(root)
  local d = sysjson({ "gh", "pr", "list", "--limit", "40", "--json",
    "number,title,author,isDraft,reviewDecision,statusCheckRollup,headRefName,baseRefName" }, root)
  if not d then return nil end
  local items = {}
  for _, p in ipairs(d) do
    local tags = {}
    if p.isDraft then tags[#tags + 1] = "✎draft" end
    if p.reviewDecision == "APPROVED" then tags[#tags + 1] = "✓approved"
    elseif p.reviewDecision == "CHANGES_REQUESTED" then tags[#tags + 1] = "✗changes" end
    tags[#tags + 1] = rollup(p.statusCheckRollup)
    items[#items + 1] = {
      id = p.number, branch = p.headRefName, base = p.baseRefName,
      display = string.format("#%-4d %-24s %s  (@%s)", p.number, table.concat(tags, " "), p.title, (p.author or {}).login or "?"),
    }
  end
  return items
end

-- structured inline comments (GitHub review comments). new_line = RIGHT-side
-- line; nil for LEFT-side/outdated comments (panel-only, no diff anchor).
local function gh_inline(root, num)
  local d = sysjson({ "gh", "api", ("repos/{owner}/{repo}/pulls/%d/comments"):format(num) }, root)
  local out = {}
  for _, c in ipairs(d or {}) do
    out[#out + 1] = {
      path = c.path,
      line = c.line or c.original_line,
      new_line = (c.side ~= "LEFT") and c.line or nil,
      who = "@" .. ((c.user or {}).login or "?"),
      body = c.body or "",
    }
  end
  return out
end

local function gh_panel_lines(root, num, inline)
  local d = sysjson({ "gh", "pr", "view", tostring(num), "--json",
    "number,title,author,body,state,isDraft,reviewDecision,statusCheckRollup,comments,baseRefName,headRefName" }, root)
  if not d then return { "# Failed to load PR #" .. num } end
  local L = {
    ("# PR #%d — %s"):format(d.number, d.title),
    ("`%s → %s` · **%s**%s · %s · review: %s"):format(d.headRefName, d.baseRefName, d.state,
      d.isDraft and " (draft)" or "", rollup(d.statusCheckRollup), d.reviewDecision or "none"),
    "by @" .. ((d.author or {}).login or "?"), "", "## Description",
  }
  for _, ln in ipairs(vim.split(body_or_none(d.body), "\n")) do L[#L + 1] = ln end
  if d.comments and #d.comments > 0 then
    L[#L + 1] = ""; L[#L + 1] = "## Comments"
    for _, c in ipairs(d.comments) do
      L[#L + 1] = "**@" .. ((c.author or {}).login or "?") .. ":**"
      for _, ln in ipairs(vim.split(c.body or "", "\n")) do L[#L + 1] = "> " .. ln end
    end
  end
  inline_section(L, inline)
  return L
end

-- Bitbucket (REST API v2.0)
local function bb_curl(path, query)
  local user, token = vim.env.BITBUCKET_USER, vim.env.BITBUCKET_TOKEN
  if not (user and token) then
    vim.notify("Set BITBUCKET_USER and BITBUCKET_TOKEN for Bitbucket PRs", vim.log.levels.ERROR)
    return nil
  end
  return sysjson({ "curl", "-s", "-u", user .. ":" .. token,
    "https://api.bitbucket.org/2.0/repositories/" .. path .. (query and ("?" .. query) or "") })
end

local function bb_prs(ws, repo)
  local d = bb_curl(("%s/%s/pullrequests"):format(ws, repo),
    "state=OPEN&pagelen=40&fields=values.id,values.title,values.author.display_name,values.draft,values.source.branch.name,values.destination.branch.name")
  if not d then return nil end
  local items = {}
  for _, p in ipairs(d.values or {}) do
    items[#items + 1] = {
      id = p.id, branch = p.source.branch.name, base = p.destination.branch.name,
      display = ("#%-4d %-8s %s  (%s)"):format(p.id, p.draft and "✎draft" or "", p.title, (p.author or {}).display_name or "?"),
    }
  end
  return items
end

local function bb_panel_lines(ws, repo, id)
  local base = ("%s/%s/pullrequests/%d"):format(ws, repo, id)
  local d = bb_curl(base, "fields=title,state,draft,summary.raw,participants.approved,participants.user.display_name,source.commit.hash,source.branch.name,destination.branch.name")
  if not d then return { "# Failed to load PR #" .. id } end
  local approvals = {}
  for _, p in ipairs(d.participants or {}) do
    if p.approved then approvals[#approvals + 1] = (p.user or {}).display_name or "?" end
  end
  local ci, sha = "—", (((d.source or {}).commit or {}).hash)
  if sha then ci = rollup((bb_curl(("%s/%s/commit/%s/statuses"):format(ws, repo, sha), "fields=values.state") or {}).values) end
  local L = {
    ("# PR #%d — %s"):format(id, d.title),
    ("`%s → %s` · **%s**%s · %s · approvals: %s"):format(
      ((d.source or {}).branch or {}).name or "?", ((d.destination or {}).branch or {}).name or "?",
      d.state, d.draft and " (draft)" or "", ci, #approvals > 0 and table.concat(approvals, ", ") or "none"),
    "", "## Description",
  }
  for _, ln in ipairs(vim.split(body_or_none((d.summary or {}).raw), "\n")) do L[#L + 1] = ln end
  -- one /comments fetch feeds both the panel and the on-diff annotations.
  local cm = bb_curl(base .. "/comments", "pagelen=50&fields=values.content.raw,values.user.display_name,values.inline.path,values.inline.to,values.inline.from")
  local general, inline = {}, {}
  for _, c in ipairs((cm or {}).values or {}) do
    local body, who = (c.content or {}).raw or "", (c.user or {}).display_name or "?"
    if c.inline then
      inline[#inline + 1] = {
        path = c.inline.path,
        line = c.inline.to or c.inline.from,
        new_line = c.inline.to, -- nil when the comment is on a removed line
        who = who, body = body,
      }
    else
      general[#general + 1] = { who = who, body = body }
    end
  end
  if #general > 0 then
    L[#L + 1] = ""; L[#L + 1] = "## Comments"
    for _, c in ipairs(general) do
      L[#L + 1] = "**" .. c.who .. ":**"
      for _, ln in ipairs(vim.split(c.body, "\n")) do L[#L + 1] = "> " .. ln end
    end
  end
  inline_section(L, inline)
  return L, inline
end

local function review_pr()
  local root = git_root_of(0)
  if not root then
    vim.notify("Not inside a git repo", vim.log.levels.ERROR)
    return
  end
  local forge, ws, repo = forge_of(root)
  if not forge then
    vim.notify("origin is not GitHub or Bitbucket", vim.log.levels.ERROR)
    return
  end
  local f = load_fzf()
  if not f then return end
  vim.notify("Loading " .. forge .. " PRs …", vim.log.levels.INFO)
  local items = (forge == "github") and gh_prs(root) or bb_prs(ws, repo)
  if not items then
    vim.notify("Failed to list PRs", vim.log.levels.ERROR)
    return
  end
  if #items == 0 then
    vim.notify("No open PRs", vim.log.levels.INFO)
    return
  end
  local lookup, displays = {}, {}
  for _, it in ipairs(items) do
    lookup[it.display] = it
    displays[#displays + 1] = it.display
  end
  f.fzf_exec(displays, {
    prompt = "PR> ",
    actions = {
      ["default"] = function(sel)
        local it = sel and sel[1] and lookup[sel[1]]
        if not it then return end
        if open_review(root, it.branch, it.base) then
          local panel, inline
          if forge == "github" then
            inline = gh_inline(root, it.id)
            panel = gh_panel_lines(root, it.id, inline)
          else
            panel, inline = bb_panel_lines(ws, repo, it.id)
          end
          pr_panel(panel)
          place_inline(inline)
          vim.notify("PR #" .. it.id .. " — <leader>gi toggles inline · <leader>gR when done", vim.log.levels.INFO)
        end
      end,
    },
  })
end

map("n", "<leader>gr", review_branch, { desc = "Review a branch/PR (worktree)" })
map("n", "<leader>gP", review_pr, { desc = "Review a forge PR (worktree + panel)" })
map("n", "<leader>gt", toggle_pr_panel, { desc = "Toggle PR panel" })
map("n", "<leader>gi", toggle_inline, { desc = "Toggle inline PR comments on diff" })
map("n", "<leader>gR", cleanup_review, { desc = "Finish PR review (remove worktree)" })

-- ---------------------------------------------------------------------------
-- <leader>gw — worktree switcher. One keybind to see every worktree of the repo
-- and jump to one — the "where has the agent been working?" map. Each row shows
-- ● current · branch · path · clean/✗dirty/(PR review)/(prunable) · last commit
-- (subject · age); rows are sorted current → dirty → clean. The fzf preview pane
-- shows the highlighted worktree's recent commits + working-tree status. Native
-- git + fzf-lua, no plugin.
--   Enter   switch: tcd into it + open its files picker
--   ctrl-n  create a new worktree (prompts a branch) and jump in
--   ctrl-x  remove the selected worktree (confirm; prunes stale entries)
-- ---------------------------------------------------------------------------
local function list_worktrees(root)
  local out = vim.system({ "git", "-C", root, "worktree", "list", "--porcelain" }, { text = true }):wait()
  if out.code ~= 0 then return {} end
  local wts, cur = {}, nil
  for _, line in ipairs(vim.split(out.stdout or "", "\n")) do
    local p = line:match("^worktree (.+)$")
    if p then
      cur = { path = p }
      wts[#wts + 1] = cur
    elseif cur then
      local b = line:match("^branch refs/heads/(.+)$")
      if b then cur.branch = b
      elseif line == "detached" then cur.branch = "(detached)"
      elseif line == "bare" then cur.branch = "(bare)"
      elseif line:match("^prunable") then cur.prunable = true end
    end
  end
  return wts
end

local function worktrees()
  local root = git_root_of(0) -- toplevel of the worktree we're currently in
  if not root then
    vim.notify("Not inside a git repo", vim.log.levels.ERROR)
    return
  end
  local f = load_fzf()
  if not f then return end
  local pr_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "pr-review")
  local wts = list_worktrees(root)
  if #wts == 0 then
    vim.notify("No worktrees", vim.log.levels.INFO)
    return
  end
  -- enrich: current/PR flags, dirty state, and last commit (subject · age)
  for _, w in ipairs(wts) do
    w.current = (w.path == root)
    w.pr = (w.path:sub(1, #pr_dir) == pr_dir)
    local st = vim.system({ "git", "-C", w.path, "status", "--porcelain" }, { text = true }):wait()
    w.dirty = st.code == 0 and vim.trim(st.stdout or "") ~= ""
    local lg = vim.system({ "git", "-C", w.path, "log", "-1", "--format=%s\31%cr" }, { text = true }):wait()
    if lg.code == 0 then w.subject, w.age = vim.trim(lg.stdout or ""):match("^(.-)\31(.*)$") end
  end
  -- sort: current → dirty (needs attention) → clean → prunable; path tiebreak
  table.sort(wts, function(a, b)
    local function rank(w) return w.current and 0 or (w.prunable and 3 or (w.dirty and 1 or 2)) end
    local ra, rb = rank(a), rank(b)
    if ra ~= rb then return ra < rb end
    return a.path < b.path
  end)
  -- entry = "<abspath>\t<display>": fzf shows only the display (--with-nth 2..);
  -- the preview command and the actions recover the path from field 1.
  local entries = {}
  for _, w in ipairs(wts) do
    local tag = w.prunable and "(prunable)" or (w.pr and "(PR review)" or (w.dirty and "✗ dirty" or "clean"))
    local subj = w.subject
        and ('"%s" · %s'):format(#w.subject > 36 and (w.subject:sub(1, 35) .. "…") or w.subject, w.age or "?")
        or ""
    local disp = ("%s %-18s %-32s %-11s %s"):format(
      w.current and "●" or " ", w.branch or "?", vim.fn.fnamemodify(w.path, ":~"), tag, subj)
    entries[#entries + 1] = w.path .. "\t" .. disp
  end
  local function path_of(sel) return sel and sel[1] and sel[1]:match("^(.-)\t") end
  -- switch cwd to a worktree and drop straight into its files picker
  local function jump(path)
    vim.cmd.tcd(vim.fn.fnameescape(path))
    vim.notify("cwd → " .. vim.fn.fnamemodify(path, ":~"), vim.log.levels.INFO)
    vim.schedule(function() f.files({ cwd = path }) end)
  end
  f.fzf_exec(entries, {
    prompt = "Worktrees> ",
    fzf_opts = { ["--delimiter"] = "\t", ["--with-nth"] = "2..", ["--no-multi"] = true },
    -- preview the highlighted worktree: recent commits + its working-tree status
    preview = "git -C {1} -c color.ui=always log --oneline -15 2>/dev/null; "
      .. "echo; echo '── working tree ──'; git -C {1} -c color.status=always status -s 2>/dev/null",
    actions = {
      ["default"] = function(sel)
        local p = path_of(sel)
        if p then jump(p) end
      end,
      ["ctrl-n"] = function()
        local name = vim.trim(vim.fn.input("New worktree branch: "))
        if name == "" then return end
        local path = vim.fs.dirname(root) .. "/" .. vim.fs.basename(root) .. "-" .. (name:gsub("[^%w._-]", "-"))
        -- new branch if it doesn't exist, else check the existing branch out
        local r = vim.system({ "git", "-C", root, "worktree", "add", "-b", name, path }, { text = true }):wait()
        if r.code ~= 0 then
          r = vim.system({ "git", "-C", root, "worktree", "add", path, name }, { text = true }):wait()
        end
        if r.code == 0 then jump(path)
        else vim.notify("worktree add failed:\n" .. (r.stderr or ""), vim.log.levels.ERROR) end
      end,
      ["ctrl-x"] = function(sel)
        local p = path_of(sel)
        if not p then return end
        if p == root then
          vim.notify("Refusing to remove the worktree you're in", vim.log.levels.WARN)
          return
        end
        if vim.fn.confirm("Remove worktree?\n" .. p, "&Yes\n&No", 2) ~= 1 then return end
        local r = vim.system({ "git", "-C", root, "worktree", "remove", "--force", p }, { text = true }):wait()
        if r.code ~= 0 then -- stale/prunable entry whose dir is already gone
          r = vim.system({ "git", "-C", root, "worktree", "prune" }, { text = true }):wait()
        end
        vim.notify(
          r.code == 0 and ("Removed " .. vim.fn.fnamemodify(p, ":~")) or ("remove failed:\n" .. (r.stderr or "")),
          r.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
      end,
    },
  })
end
map("n", "<leader>gw", worktrees, { desc = "Worktrees: list / switch / create / remove" })

-- ---------------------------------------------------------------------------
-- Python virtualenv: auto-detect + an fzf-lua picker to switch (no new plugin).
-- ty/ruff locate site-packages from $VIRTUAL_ENV, and ty only auto-detects a
-- `.venv` in its OWN project root — which misses monorepos that share a single
-- `.venv` ABOVE the per-package pyproject.toml. So find the nearest venv by
-- walking up from the file and export VIRTUAL_ENV before the servers start.
-- A venv already activated in the shell always wins and is never overridden.
-- ---------------------------------------------------------------------------
local function find_venvs_up(start)
  local hits = vim.fs.find({ ".venv", "venv", "env" }, {
    path = start, upward = true, type = "directory", limit = 10,
  })
  return vim.tbl_filter(function(d)
    return vim.fn.filereadable(d .. "/bin/python") == 1
      or vim.fn.filereadable(d .. "/Scripts/python.exe") == 1
  end, hits)
end

local shell_venv = (vim.env.VIRTUAL_ENV and vim.fn.isdirectory(vim.env.VIRTUAL_ENV) == 1)
  and vim.env.VIRTUAL_ENV or nil
local venv_override = nil -- set by the <leader>v picker

local function venv_for(buf)
  if shell_venv then return shell_venv end
  if venv_override then return venv_override end
  return find_venvs_up(vim.api.nvim_buf_get_name(buf))[1]
end

-- Registered BEFORE vim.lsp.enable below, so it runs first on FileType and the
-- servers start already pointed at the right environment (no restart needed).
vim.api.nvim_create_autocmd("FileType", {
  group = aug,
  pattern = "python",
  callback = function(args)
    local v = venv_for(args.buf)
    if v then vim.env.VIRTUAL_ENV = v end
  end,
})

local function restart_python_lsp()
  local buf = vim.api.nvim_get_current_buf()
  for _, c in ipairs(vim.lsp.get_clients()) do
    if c.name == "ty" or c.name == "ruff" then c:stop() end
  end
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_exec_autocmds("FileType", { buffer = buf })
    end
  end, 250)
end

-- <leader>v — venv dashboard: lists discovered venvs (project + ~/.virtualenvs),
-- marks the active one, shows whether each has ipykernel, and lets you switch
-- (<CR>) or install ipykernel into the highlighted one (i). Same dashboard style
-- as <leader>l: aligned columns + coloured glyphs, navigated with j/k.
local venv_ns = vim.api.nvim_create_namespace("venv_picker")

local function venv_label(p)
  local b = vim.fs.basename(p)
  if b == ".venv" or b == "venv" or b == "env" then b = vim.fs.basename(vim.fs.dirname(p)) end
  return b
end
local function venv_python(v)
  if vim.fn.filereadable(v .. "/bin/python") == 1 then return v .. "/bin/python" end
  return v .. "/Scripts/python.exe"
end
local function venv_has_ipykernel(v)
  return #vim.fn.glob(v .. "/lib/python*/site-packages/ipykernel", true, true) > 0
    or #vim.fn.glob(v .. "/Lib/site-packages/ipykernel", true, true) > 0
end
local function venv_collect()
  local seen, items = {}, {}
  local function add(p)
    p = vim.fn.fnamemodify(p, ":p"):gsub("/+$", "")
    if not seen[p] and vim.fn.isdirectory(p) == 1 then
      seen[p] = true
      items[#items + 1] = p
    end
  end
  local alt = vim.fn.bufnr("#")
  if alt > 0 then
    for _, v in ipairs(find_venvs_up(vim.api.nvim_buf_get_name(alt))) do add(v) end
  end
  for _, v in ipairs(find_venvs_up(vim.fn.getcwd())) do add(v) end
  for _, v in ipairs(vim.fn.glob("~/.virtualenvs/*", true, true)) do add(v) end -- glob expands ~ and *
  return items
end

local function venv_populate(b)
  local lines, marks, rowmap = {}, {}, {}
  local function add(segs)
    local text, col = "", 0
    for _, s in ipairs(segs or {}) do
      local t = s[1] or ""
      if s[2] and t ~= "" then marks[#marks + 1] = { #lines, col, col + #t, s[2] } end
      text, col = text .. t, col + #t
    end
    lines[#lines + 1] = text
  end
  add({ { "  " .. (vim.g.have_nerd_font and "\u{e73c} " or "") .. "VENV", "Title" } })
  add({ { "  " .. ("─"):rep(58), "Comment" } })
  add({})
  local active = vim.env.VIRTUAL_ENV
  if active and active ~= "" then active = vim.fn.fnamemodify(active, ":p"):gsub("/+$", "") end
  local items = venv_collect()
  if #items == 0 then
    add({ { "    no virtualenvs found", "Comment" } })
  else
    for _, v in ipairs(items) do
      local cur, kern = v == active, venv_has_ipykernel(v)
      add({
        { "  " },
        { cur and "● " or "  ", cur and "DiagnosticOk" or nil },
        { ("%-18s"):format(venv_label(v)) },
        { kern and "✓ ipykernel" or "✗ no kernel", kern and "DiagnosticOk" or "DiagnosticHint" },
        { "  " },
        { vim.fn.fnamemodify(v, ":~"), "Comment" },
      })
      rowmap[#lines] = v
    end
  end
  add({})
  add({
    { "  ↵", "Function" }, { " select   ", "Comment" },
    { "i", "Function" }, { " install ipykernel   ", "Comment" },
    { "q", "Function" }, { " close", "Comment" },
  })
  vim.bo[b].modifiable = true
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(b, venv_ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, b, venv_ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  vim.bo[b].modifiable = false
  _G.__venv_rowmap = rowmap
end

local function venv_under_cursor()
  return _G.__venv_rowmap and _G.__venv_rowmap[vim.api.nvim_win_get_cursor(0)[1]]
end
local function venv_close()
  if _G.__venv_win and vim.api.nvim_win_is_valid(_G.__venv_win) then
    vim.api.nvim_win_close(_G.__venv_win, true)
  end
  _G.__venv_win = nil
end
local function venv_select()
  local v = venv_under_cursor()
  if not v then return end
  venv_override = v
  vim.env.VIRTUAL_ENV = v
  venv_close()
  vim.notify("venv → " .. venv_label(v), vim.log.levels.INFO)
  restart_python_lsp()
end
local function venv_install()
  local v = venv_under_cursor()
  if not v then return end
  if venv_has_ipykernel(v) then
    vim.notify(venv_label(v) .. " already has ipykernel", vim.log.levels.INFO)
    return
  end
  local py = venv_python(v)
  local cmd = vim.fn.executable("uv") == 1 and { "uv", "pip", "install", "--python", py, "ipykernel" }
    or { py, "-m", "pip", "install", "ipykernel" }
  vim.notify("Installing ipykernel into " .. venv_label(v) .. " …", vim.log.levels.INFO)
  local b = vim.api.nvim_get_current_buf()
  vim.system(cmd, { text = true }, function(r)
    vim.schedule(function()
      if r.code == 0 then
        vim.notify("ipykernel installed in " .. venv_label(v), vim.log.levels.INFO)
        if vim.api.nvim_buf_is_valid(b) then venv_populate(b) end -- refresh the ✓/✗
      else
        vim.notify("ipykernel install failed:\n" .. (r.stderr or ""), vim.log.levels.ERROR)
      end
    end)
  end)
end

vim.keymap.set("n", "<leader>v", function()
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "wipe"
  venv_populate(b)
  local width = 64
  local height = math.min(vim.api.nvim_buf_line_count(b), math.floor(vim.o.lines * 0.85))
  _G.__venv_win = vim.api.nvim_open_win(b, true, {
    relative = "editor", width = width, height = height,
    col = math.floor((vim.o.columns - width) / 2), row = math.floor((vim.o.lines - height) / 2),
    style = "minimal", border = "rounded", title = " python venv ", title_pos = "center",
  })
  vim.wo[_G.__venv_win].cursorline = true
  local first
  for ln in pairs(_G.__venv_rowmap or {}) do
    if not first or ln < first then first = ln end
  end
  if first then vim.api.nvim_win_set_cursor(_G.__venv_win, { first, 0 }) end
  local opts = { buffer = b, nowait = true }
  vim.keymap.set("n", "<CR>", venv_select, opts)
  vim.keymap.set("n", "i", venv_install, opts)
  vim.keymap.set("n", "q", venv_close, opts)
  vim.keymap.set("n", "<Esc>", venv_close, opts)
end, { desc = "Python venv dashboard (switch / install ipykernel)" })

-- ---------------------------------------------------------------------------
-- Dynamic Python REPL — select code, run it in a persistent ipykernel, see the
-- output inline (ephemeral virtual lines under the selection; never touches the
-- buffer). State persists across sends, so it's a real REPL. nvim stays
-- plugin-free: a tiny daemon (python/jrepl.py) runs in the ACTIVE VENV's python
-- and speaks line-JSON over stdio; we only render. Needs `ipykernel` in the
-- venv — absent → the keymaps no-op with a hint, so portability is preserved.
--   x  <leader>r   run the selection      n  <leader>r   run the paragraph
--   n  <leader>rc  clear inline outputs   n  <leader>rk  restart the kernel
-- ---------------------------------------------------------------------------
local repl = _G.__py_repl or { job = nil, ready = false, seq = 0, pending = {}, queue = {}, acc = "" }
_G.__py_repl = repl
repl.placed = repl.placed or {}     -- id -> { buf, span }: which code block each output covers
repl.attached = repl.attached or {} -- buf -> true: on_lines hooked (clears output only on code edits)
repl.stderr = repl.stderr or ""     -- tail of the daemon's stderr, for failure messages
local repl_ns = vim.api.nvim_create_namespace("py_repl")

local function repl_render(p)
  if not vim.api.nvim_buf_is_valid(p.buf) then return end
  local vlines, n = {}, 0
  for _, seg in ipairs(p.parts) do
    -- dim everything (a quiet "  ╎ " rail, no arrows); only errors keep colour
    local hl = seg.kind == "error" and "DiagnosticError" or "Comment"
    for _, ln in ipairs(vim.split((seg.text or ""):gsub("\n$", ""), "\n", { plain = true })) do
      n = n + 1
      if n > 200 then
        vlines[#vlines + 1] = { { "╎ … (output truncated)", "Comment" } }
        goto done
      end
      vlines[#vlines + 1] = { { "╎ " .. ln, hl } }
    end
  end
  ::done::
  pcall(vim.api.nvim_buf_set_extmark, p.buf, repl_ns, p.row, 0, { id = p.id, virt_lines = vlines })
end

-- resolve every still-running placeholder to an error so nothing hangs on
-- "starting kernel…" when the daemon dies or never comes up
local function repl_fail(msg)
  for id, p in pairs(repl.pending) do
    p.parts, p.running = { { kind = "error", text = msg } }, false
    vim.schedule(function() repl_render(p) end)
    repl.pending[id] = nil
  end
  vim.schedule(function() vim.notify("Python REPL: " .. msg, vim.log.levels.ERROR) end)
end

local function repl_process(line)
  if line == "" then return end
  local ok, m = pcall(vim.json.decode, line)
  if not ok or type(m) ~= "table" then return end
  if m.type == "ready" then
    repl.ready = true
    for _, payload in ipairs(repl.queue) do vim.fn.chansend(repl.job, payload) end
    repl.queue = {}
    -- queued sends showed "starting kernel…"; they're actually running now
    for _, p in pairs(repl.pending) do
      if p.running then p.parts = { { kind = "running", text = "running…" } } end
    end
    vim.schedule(function() for _, p in pairs(repl.pending) do repl_render(p) end end)
    return
  end
  if m.type == "fatal" then
    repl_fail(m.text or "kernel error")
    return
  end
  local p = repl.pending[m.id]
  if not p then return end
  if m.type == "done" then
    if p.running and #p.parts <= 1 then p.parts = { { kind = "ok", text = "✓ (no output)" } } end
    p.running = false
    repl.pending[m.id] = nil
  else
    if p.running then p.parts = {}; p.running = false end -- drop the "running…" placeholder
    p.parts[#p.parts + 1] = { kind = m.type, text = m.text or "" }
  end
  vim.schedule(function() repl_render(p) end)
end

local function repl_on_stdout(_, data)
  if not data then return end
  data[1] = repl.acc .. data[1]
  repl.acc = table.remove(data) or ""
  for _, line in ipairs(data) do repl_process(line) end
end

local function repl_ensure()
  if repl.job and repl.job > 0 then return true end
  local venv = venv_for(0)
  local py = venv and (venv .. (is_windows and "/Scripts/python.exe" or "/bin/python")) or "python3"
  if vim.system({ py, "-c", "import ipykernel" }, { text = true }):wait().code ~= 0 then
    vim.notify("Python REPL needs ipykernel in the active venv:\n  uv pip install ipykernel", vim.log.levels.WARN)
    return false
  end
  local daemon = vim.fs.joinpath(vim.fn.stdpath("config"), "python", "jrepl.py")
  repl.ready, repl.queue, repl.acc, repl.stderr = false, {}, "", ""
  repl.job = vim.fn.jobstart({ py, daemon }, {
    on_stdout = repl_on_stdout,
    on_stderr = function(_, d)
      local s = d and vim.trim(table.concat(d, "\n")) or ""
      if s ~= "" then repl.stderr = (repl.stderr .. "\n" .. s):sub(-600) end
    end,
    on_exit = function()
      local hanging = false
      for _, p in pairs(repl.pending) do if p.running then hanging = true end end
      repl.job, repl.ready, repl.queue = nil, false, {}
      -- a daemon that dies while a send is still "starting/running" must not
      -- leave that placeholder stuck — surface why (kernel start usually)
      if hanging then repl_fail("kernel exited" .. (repl.stderr ~= "" and ("\n" .. repl.stderr) or "")) end
    end,
  })
  if repl.job <= 0 then
    repl.job = nil
    vim.notify("Python REPL: failed to launch kernel daemon", vim.log.levels.ERROR)
    return false
  end
  -- no notify here: the inline "starting kernel… → running…" placeholder under
  -- the code already shows status, and a notify would linger in the message bar
  return true
end

-- Hook the buffer so an output clears ONLY when an edit touches the code lines
-- that produced it. Editing elsewhere — e.g. opening a line just below the
-- output — leaves it in place. on_lines just reads/deletes extmarks (no text
-- change), and deletions are scheduled to stay off the fast path.
local function repl_attach(buf)
  if repl.attached[buf] then return end
  repl.attached[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, _, first, last_old, last_new)
      local change_end = math.max(last_old, last_new)
      for id, m in pairs(repl.placed) do
        if m.buf == b then
          local pos = vim.api.nvim_buf_get_extmark_by_id(b, repl_ns, id, {})
          local row = pos and pos[1]
          if not row then
            repl.placed[id] = nil
          elseif first <= row and change_end > row - m.span then -- edit hit the code block
            repl.placed[id], repl.pending[id] = nil, nil
            vim.schedule(function() pcall(vim.api.nvim_buf_del_extmark, b, repl_ns, id) end)
          end
        end
      end
    end,
    on_detach = function(_, b) repl.attached[b] = nil end,
  })
end

local function repl_send(buf, s, e)
  local lines = vim.api.nvim_buf_get_lines(buf, s - 1, e, false)
  local code_lines = {}
  for _, l in ipairs(lines) do -- drop ``` / ~~~ fences (safe inside a markdown block)
    if not l:match("^%s*```") and not l:match("^%s*~~~") then code_lines[#code_lines + 1] = l end
  end
  -- dedent the common leading whitespace so indented blocks run standalone
  local min
  for _, l in ipairs(code_lines) do
    if not l:match("^%s*$") then
      local w = #l:match("^%s*")
      if not min or w < min then min = w end
    end
  end
  if min and min > 0 then
    for i, l in ipairs(code_lines) do code_lines[i] = l:sub(min + 1) end
  end
  local code = table.concat(code_lines, "\n")
  if vim.trim(code) == "" then return end
  if not repl_ensure() then return end
  repl.seq = repl.seq + 1
  local id = repl.seq
  local p = { id = id, buf = buf, row = e - 1, running = true,
    parts = { { kind = "running", text = repl.ready and "running…" or "starting kernel…" } } }
  repl.pending[id] = p
  repl.placed[id] = { buf = buf, span = e - s } -- code occupies [anchorRow - span .. anchorRow]
  repl_attach(buf)
  repl_render(p)
  local payload = vim.json.encode({ id = id, code = code }) .. "\n"
  if repl.ready then vim.fn.chansend(repl.job, payload) else repl.queue[#repl.queue + 1] = payload end
end

local function repl_run_visual()
  local buf = vim.api.nvim_get_current_buf()
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then s, e = e, s end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  repl_send(buf, s, e)
end

-- In a markdown buffer, find the ```python / ```py fence enclosing the cursor;
-- returns the body's 1-indexed [start, end] (between the fences), or nil.
local function md_python_block(buf, cur)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local open, lang
  for i, l in ipairs(lines) do
    if l:match("^%s*```") or l:match("^%s*~~~") then
      if not open then
        open, lang = i, (l:match("^%s*[`~]+%s*(%S+)") or ""):lower()
      else
        if (lang == "python" or lang == "py") and cur >= open and cur <= i then
          return open + 1, i - 1
        end
        open, lang = nil, nil
      end
    end
  end
end

local function repl_run_paragraph()
  local buf = vim.api.nvim_get_current_buf()
  local cur, last = vim.fn.line("."), vim.fn.line("$")
  if (vim.bo[buf].filetype or ""):match("markdown") then
    local s, e = md_python_block(buf, cur)
    if not s then
      vim.notify("Not inside a ```python code block", vim.log.levels.WARN)
      return
    end
    repl_send(buf, s, e)
    return
  end
  local s, e = cur, cur
  if not vim.fn.getline(cur):match("^%s*$") then
    while s > 1 and not vim.fn.getline(s - 1):match("^%s*$") do s = s - 1 end
    while e < last and not vim.fn.getline(e + 1):match("^%s*$") do e = e + 1 end
  end
  repl_send(buf, s, e)
end

local function repl_clear(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(buf, repl_ns, 0, -1)
  for id, p in pairs(repl.pending) do if p.buf == buf then repl.pending[id] = nil end end
  for id, m in pairs(repl.placed) do if m.buf == buf then repl.placed[id] = nil end end
end

map("x", "<leader>r", repl_run_visual, { desc = "Python REPL: run selection" })
-- normal-mode run is <leader>rr (not bare <leader>r) so it doesn't wait
-- timeoutlen for the rc/rk siblings; visual <leader>r has no siblings, stays snappy
map("n", "<leader>rr", repl_run_paragraph, { desc = "Python REPL: run paragraph" })
map("n", "<leader>rc", function() repl_clear() end, { desc = "Python REPL: clear outputs" })
map("n", "<leader>rk", function()
  repl_clear()
  if repl.job and repl.job > 0 then
    vim.fn.chansend(repl.job, vim.json.encode({ id = 0, restart = true }) .. "\n")
    vim.notify("Python kernel restarted (fresh state)", vim.log.levels.INFO)
  else
    vim.notify("No Python kernel running", vim.log.levels.INFO)
  end
end, { desc = "Python REPL: restart kernel" })

-- ---------------------------------------------------------------------------
-- LSP: ty + ruff (Python), rust-analyzer (Rust). Servers are only *enabled*
-- when their binary is installed, so a machine without the toolchain opens
-- .py/.rs files cleanly instead of erroring with "command not found".
-- ---------------------------------------------------------------------------
vim.lsp.config("ty", {
  cmd = { "ty", "server" },
  filetypes = { "python" },
  root_markers = { "ty.toml", "pyproject.toml", "setup.py", "setup.cfg", ".git" },
})

vim.lsp.config("ruff", {
  cmd = { "ruff", "server" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
})

-- Locate a runnable rust-analyzer. Prefer it on PATH; otherwise find the rustup
-- toolchain binary directly (some rustup installs — e.g. Arch's system package —
-- ship no rust-analyzer proxy on PATH). Glob, not `rustup which`, to keep zero
-- subprocess cost at startup. nil ⇒ Rust LSP simply stays off.
local function find_rust_analyzer()
  if vim.fn.executable("rust-analyzer") == 1 then return { "rust-analyzer" } end
  if vim.fn.executable("rustup") == 1 then
    local home = vim.env.RUSTUP_HOME or ((vim.env.HOME or "") .. "/.rustup")
    local hits = vim.fn.glob(home .. "/toolchains/*/bin/rust-analyzer", true, true)
    for _, h in ipairs(hits) do
      if h:find("stable", 1, true) then return { h } end -- prefer the stable toolchain
    end
    if hits[1] then return { hits[1] } end
  end
end
local ra_cmd = find_rust_analyzer()

-- Rust: rust-analyzer with clippy-on-save (richer lints than `cargo check`),
-- proc-macro support, and all cargo features. Inlay hints are turned on per
-- buffer in LspAttach below (toggle with <leader>uh).
vim.lsp.config("rust_analyzer", {
  cmd = ra_cmd or { "rust-analyzer" },
  filetypes = { "rust" },
  root_markers = { "Cargo.toml", "rust-project.json", ".git" },
  settings = {
    ["rust-analyzer"] = {
      check = { command = "clippy" },
      cargo = { allFeatures = true },
      procMacro = { enable = true },
    },
  },
})

-- Lua: lua-language-server, tuned for editing THIS config — it's told about the
-- Neovim runtime so `vim.*` gets completion/hover/signatures, and that `vim` is
-- a global (no "undefined global" noise). No format-on-save (don't reflow your
-- hand-formatted config); <leader>F still formats on demand.
vim.lsp.config("lua_ls", {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = { ".luarc.json", ".luarc.jsonc", "stylua.toml", ".stylua.toml", ".git" },
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      workspace = { library = { vim.env.VIMRUNTIME }, checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
})

-- Enable a server only when its tool is actually present — otherwise opening a
-- file errors with "command not found" on a machine without the tool.
local lsp_on = {}
if vim.fn.executable("ty") == 1 then lsp_on[#lsp_on + 1] = "ty" end
if vim.fn.executable("ruff") == 1 then lsp_on[#lsp_on + 1] = "ruff" end
if vim.fn.executable("lua-language-server") == 1 then lsp_on[#lsp_on + 1] = "lua_ls" end
if ra_cmd then lsp_on[#lsp_on + 1] = "rust_analyzer" end
if #lsp_on > 0 then vim.lsp.enable(lsp_on) end

-- ---------------------------------------------------------------------------
-- Hover cleanup: ty (and others) emit docstrings containing HTML entities
-- (&nbsp; for indentation) and CommonMark backslash escapes (plain\_text),
-- which the float renders literally. Decode them so `K` reads cleanly.
-- ---------------------------------------------------------------------------
local function clean_markup(s)
  if type(s) ~= "string" then return s end
  s = s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<")
    :gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'")
  s = s:gsub("\\(%p)", "%1") -- strip CommonMark backslash escapes
  return s
end

-- Capture the pristine default once (in _G) so re-sourcing on hot-reload never
-- nests this wrapper inside a previous copy of itself.
_G.__orig_hover = _G.__orig_hover or vim.lsp.handlers["textDocument/hover"] or vim.lsp.handlers.hover
local orig_hover = _G.__orig_hover
vim.lsp.handlers["textDocument/hover"] = function(err, result, ctx, config)
  local c = result and result.contents
  if type(c) == "table" then
    if c.value then
      c.value = clean_markup(c.value)
    else
      for i, item in ipairs(c) do
        if type(item) == "string" then
          c[i] = clean_markup(item)
        elseif type(item) == "table" then
          item.value = clean_markup(item.value)
        end
      end
    end
  elseif type(c) == "string" then
    result.contents = clean_markup(c)
  end
  return orig_hover(err, result, ctx, config)
end

-- ---------------------------------------------------------------------------
-- LSP buffer behaviour & keymaps (attached per-buffer when a server connects)
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
  group = aug,
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    -- Let ty own hover; ruff focuses on lint/format to avoid double hovers.
    if client and client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end

    -- As-you-type completion via the built-in LSP completion engine (no plugin).
    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
    end

    -- Inlay hints (inferred types / param names) for any server that does them
    -- — rust-analyzer, ty, lua_ls, … — toggle per buffer with <leader>uh.
    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end

    local function bmap(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc })
    end

    bmap("gd", vim.lsp.buf.definition, "Go to definition")
    bmap("gD", vim.lsp.buf.declaration, "Go to declaration")
    bmap("gi", vim.lsp.buf.implementation, "Go to implementation")
    bmap("gy", vim.lsp.buf.type_definition, "Type definition")
    bmap("gr", function()
      local f = load_fzf()
      if f then f.lsp_references() else vim.lsp.buf.references() end
    end, "References")
    bmap("K", vim.lsp.buf.hover, "Hover")
    bmap("<leader>rn", vim.lsp.buf.rename, "Rename")
    bmap("<leader>ca", vim.lsp.buf.code_action, "Code action")
    bmap("<leader>d", vim.diagnostic.open_float, "Line diagnostics")
    bmap("[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Prev diagnostic")
    bmap("]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
    bmap("<leader>F", function() vim.lsp.buf.format({ async = false }) end, "Format buffer")
  end,
})

-- ---------------------------------------------------------------------------
-- Format Python on save with ruff (ty does not format). Skips the big-file
-- guard's large buffers so saving a huge file stays instant.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("BufWritePre", {
  group = aug,
  pattern = "*.py",
  callback = function(args)
    if vim.b[args.buf].large_file then return end
    vim.lsp.buf.format({
      bufnr = args.buf,
      async = false,
      filter = function(c) return c.name == "ruff" end,
    })
  end,
})

-- Format Rust on save with rustfmt (via rust-analyzer). No-ops if the server
-- didn't attach (toolchain absent), so it's naturally gated like the Python one.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = aug,
  pattern = "*.rs",
  callback = function(args)
    if vim.b[args.buf].large_file then return end
    vim.lsp.buf.format({
      bufnr = args.buf,
      async = false,
      filter = function(c) return c.name == "rust_analyzer" end,
    })
  end,
})

-- ---------------------------------------------------------------------------
-- <leader>l — LSP status / debug in a floating window (toggle). Shows what's
-- attached to this buffer, every running client, which configured servers are
-- available (and which aren't), plus copy-paste debug steps and the tail of any
-- recent log errors. No plugin — there's no :LspInfo without nvim-lspconfig.
-- ---------------------------------------------------------------------------
-- non-deprecated log path (vim.lsp.get_log_path() is deprecated in 0.12)
local function lsp_log_path()
  if vim.lsp.log and vim.lsp.log.get_filename then return vim.lsp.log.get_filename() end
  return vim.fn.stdpath("log") .. "/lsp.log"
end

-- Neovim logs EVERYTHING a server prints to stderr at [ERROR] level, so the log
-- is full of benign INFO/WARN banners ("Python version: 3.12", "Server shut
-- down", the file-watching warning, …). Keep only lines that look like a real
-- failure — non-stderr RPC/protocol errors, or stderr whose payload mentions a
-- hard fault (panic/traceback/exception/fatal/error:).
local function lsp_is_real_error(line)
  if not line:find("[ERROR]", 1, true) then return false end
  if line:find('"stderr"', 1, true) then
    local low = line:lower()
    return low:find("panic") or low:find("traceback") or low:find("exception")
      or low:find("fatal") or low:find("error:") or low:find("errored") or false
  end
  return true
end

local function lsp_tail_errors(path, n)
  local f = io.open(path, "r")
  if not f then return {} end
  local size = f:seek("end")
  f:seek("set", math.max(0, size - 65536)) -- only scan the last 64 KB
  local chunk = f:read("*a") or ""
  f:close()
  local errs = {}
  for line in chunk:gmatch("[^\n]+") do
    if lsp_is_real_error(line) then errs[#errs + 1] = line end
  end
  local out = {}
  for i = math.max(1, #errs - n + 1), #errs do out[#out + 1] = errs[i] end
  return out
end

-- Build the dashboard as (lines, marks): each row is a list of {text, hl?}
-- segments, so we get aligned columns with coloured status glyphs — not markdown.
local lsp_status_ns = vim.api.nvim_create_namespace("lsp_status")
local function lsp_dashboard(buf)
  local lines, marks = {}, {}
  local function add(segs)
    local text, col = "", 0
    for _, s in ipairs(segs or {}) do
      local t = s[1] or ""
      if s[2] and t ~= "" then marks[#marks + 1] = { #lines, col, col + #t, s[2] } end
      text, col = text .. t, col + #t
    end
    lines[#lines + 1] = text
  end
  local function trunc(s, n) s = s or ""; return vim.fn.strchars(s) > n and (s:sub(1, n - 1) .. "…") or s end
  local function header(label) add({ { "  " }, { label, "Title" } }) end

  buf = buf or vim.api.nvim_get_current_buf()
  local running = {}
  for _, c in ipairs(vim.lsp.get_clients()) do running[c.name] = c.id end

  add({ { "  " .. (vim.g.have_nerd_font and "󰒋 " or "") .. "LSP", "Title" } })
  add({ { "  " .. ("─"):rep(58), "Comment" } })
  add({})

  -- Buffer: who's attached here
  header("BUFFER  " .. (vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "—"))
  local attached = vim.lsp.get_clients({ bufnr = buf })
  if #attached == 0 then
    add({ { "    no client attached", "Comment" } })
  else
    for _, c in ipairs(attached) do
      add({
        { "    " }, { "● ", "DiagnosticOk" }, { ("%-14s"):format(c.name) },
        { "#" .. c.id .. "  ", "Comment" }, { trunc(vim.fn.fnamemodify(c.root_dir or "", ":~"), 34), "Comment" },
      })
    end
  end
  add({})

  -- Servers: configured ↔ available ↔ running
  header("SERVERS")
  local servers = {
    { "ty", function() return vim.fn.executable("ty") == 1 end, "uv tool install ty" },
    { "ruff", function() return vim.fn.executable("ruff") == 1 end, "uv tool install ruff" },
    { "lua_ls", function() return vim.fn.executable("lua-language-server") == 1 end, "install lua-language-server" },
    { "rust_analyzer", function() return vim.fn.executable("rust-analyzer") == 1 or vim.fn.executable("rustup") == 1 end, "rustup component add rust-analyzer" },
  }
  for _, s in ipairs(servers) do
    local name, present = s[1], s[2]()
    local glyph, ghl, status, shl
    if running[name] then
      glyph, ghl, status, shl = "● ", "DiagnosticOk", "running", "DiagnosticOk"
    elseif present then
      glyph, ghl, status, shl = "○ ", "DiagnosticHint", "idle", "Comment"
    else
      glyph, ghl, status, shl = "✗ ", "DiagnosticError", s[3], "Comment"
    end
    add({ { "    " }, { glyph, ghl }, { ("%-15s"):format(name) }, { status, shl } })
  end
  add({})

  -- Debug: copy-paste steps
  header("DEBUG")
  local function kv(k, v) add({ { "    " }, { ("%-8s"):format(k), "Function" }, { trunc(v, 46), "Comment" } }) end
  kv("log", lsp_log_path())
  kv("open", ":lua vim.cmd.edit(vim.lsp.log.get_filename())")
  kv("verbose", ":lua vim.lsp.set_log_level('debug')")
  kv("health", ":checkhealth vim.lsp")
  add({})

  -- Recent errors, if any
  local errs = lsp_tail_errors(lsp_log_path(), 5)
  if #errs > 0 then
    header("RECENT ERRORS")
    for _, e in ipairs(errs) do
      add({ { "    " }, { "▸ ", "DiagnosticError" }, { trunc(e:gsub("%s+", " "), 52), "Comment" } })
    end
    add({})
  end

  add({
    { "  r", "Function" }, { " restart   ", "Comment" },
    { "c", "Function" }, { " copy errors   ", "Comment" },
    { "q", "Function" }, { " close", "Comment" },
  })
  return lines, marks
end

local function lsp_status_render(b, src)
  local lines, marks = lsp_dashboard(src)
  vim.bo[b].modifiable = true
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(b, lsp_status_ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, b, lsp_status_ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  vim.bo[b].modifiable = false
  return #lines
end

-- Restart the LSP clients on a buffer: stop them, then re-attach. Reloading the
-- buffer (:edit) re-runs BufReadPost/FileType and reliably brings fresh clients
-- up; for an unsaved buffer (can't reload) we re-fire FileType instead.
local function lsp_restart(src)
  if not (src and vim.api.nvim_buf_is_valid(src)) then return end
  local clients = vim.lsp.get_clients({ bufnr = src })
  for _, c in ipairs(clients) do c:stop() end
  vim.notify(#clients > 0 and ("Restarting " .. #clients .. " LSP client(s)…") or "No LSP clients on that buffer",
    vim.log.levels.INFO)
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(src) then return end
    if vim.bo[src].modified then
      vim.api.nvim_exec_autocmds("FileType", { buffer = src })
    else
      vim.api.nvim_buf_call(src, function() vim.cmd("silent! edit") end)
    end
  end, 300)
end

local function toggle_lsp_status()
  local w = _G.__lsp_status_win
  if w and vim.api.nvim_win_is_valid(w) then
    vim.api.nvim_win_close(w, true)
    _G.__lsp_status_win = nil
    return
  end
  local src = vim.api.nvim_get_current_buf() -- the buffer we came from (for restart + status)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = "wipe"
  local nlines = lsp_status_render(b, src)
  local width = 64
  local height = math.min(nlines, math.floor(vim.o.lines * 0.85))
  _G.__lsp_status_win = vim.api.nvim_open_win(b, true, {
    relative = "editor", width = width, height = height,
    col = math.floor((vim.o.columns - width) / 2), row = math.floor((vim.o.lines - height) / 2),
    style = "minimal", border = "rounded", title = " status ", title_pos = "center",
  })
  vim.wo[_G.__lsp_status_win].cursorline = true
  local opts = { buffer = b, nowait = true }
  vim.keymap.set("n", "q", "<cmd>close<cr>", opts)
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", opts)
  vim.keymap.set("n", "r", function()
    lsp_restart(src)
    vim.defer_fn(function() -- refresh once clients have re-attached
      if _G.__lsp_status_win and vim.api.nvim_win_is_valid(_G.__lsp_status_win) and vim.api.nvim_buf_is_valid(b) then
        lsp_status_render(b, src)
      end
    end, 800)
  end, opts)
  vim.keymap.set("n", "c", function() -- copy recent log errors to the clipboard
    local errs = lsp_tail_errors(lsp_log_path(), 30)
    if #errs == 0 then
      vim.notify("No recent LSP log errors", vim.log.levels.INFO)
      return
    end
    local text = table.concat(errs, "\n")
    vim.fn.setreg("+", text) -- system clipboard (OSC 52 over SSH)
    vim.fn.setreg('"', text)
    vim.notify(("Copied %d LSP log error line(s)"):format(#errs), vim.log.levels.INFO)
  end, opts)
end
map("n", "<leader>l", toggle_lsp_status, { desc = "LSP status / debug (float)" })

-- ---------------------------------------------------------------------------
-- General keymaps
-- ---------------------------------------------------------------------------
-- Toggle inlay hints (on by default for any LSP that provides them)
map("n", "<leader>uh", function()
  local on = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
  vim.lsp.inlay_hint.enable(not on, { bufnr = 0 })
  vim.notify("Inlay hints " .. (on and "off" or "on"), vim.log.levels.INFO)
end, { desc = "Toggle inlay hints" })
map("n", "<leader>w", "<cmd>write<cr>", { desc = "Save" })
-- Close the current buffer but KEEP the window/split (plain :bd closes the
-- split — or quits nvim — on your last buffer). Refuses if there are unsaved
-- changes (:w first, or :bd! to force).
map("n", "<leader>q", function()
  local cur = vim.api.nvim_get_current_buf()
  if vim.bo[cur].modified then
    vim.notify("Unsaved changes — :w first, or :bd! to force", vim.log.levels.WARN)
    return
  end
  local alt = vim.fn.bufnr("#")
  if alt > 0 and alt ~= cur and vim.fn.buflisted(alt) == 1 then
    vim.cmd.buffer("#")
  else
    vim.cmd.bprevious()
  end
  if vim.api.nvim_get_current_buf() == cur then vim.cmd.enew() end -- was the only buffer
  pcall(vim.cmd.bdelete, cur)
end, { desc = "Close buffer (keep window)" })
map("n", "<leader>e", "<cmd>Explore<cr>", { desc = "Explore (netrw)" })
-- cd to the current file's directory (so fzf-lua pickers follow you there)
map("n", "<leader>cd", function()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" then return end
  vim.cmd.tcd(vim.fn.fnameescape(dir))
  vim.notify("cwd → " .. dir, vim.log.levels.INFO)
end, { desc = "cd to current file's dir" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("n", "<C-h>", "<C-w>h"); map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k"); map("n", "<C-l>", "<C-w>l")
-- Zoom the current window fullscreen and back (<leader><Esc>). Opens the window
-- in a throwaway tab, so toggling off restores the underlying split layout
-- exactly. Works in any window, including diffview panes. vim.t.zoomed tags it.
local function toggle_zoom()
  if vim.t.zoomed then
    vim.cmd("tabclose")
  elseif vim.fn.winnr("$") > 1 then
    vim.cmd("tab split")
    vim.t.zoomed = true
  end
end
map("n", "<leader><Esc>", toggle_zoom, { desc = "Zoom window fullscreen (toggle)" })

-- ---------------------------------------------------------------------------
-- Auto-reload files changed on disk (Claude agents / remote tools editing
-- underneath you). autoread is on, but Neovim only reloads when it *checks* —
-- so poll on focus / buffer-enter / idle. Only buffers with NO unsaved changes
-- reload; if you also edited the buffer, Neovim keeps yours and warns (W12) —
-- no silent clobber. Use :DiffOrig to see what changed, then reconcile.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = aug,
  callback = function()
    if vim.bo.buftype == "" and vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = aug,
  callback = function()
    vim.notify("Buffer reloaded — file changed on disk", vim.log.levels.INFO)
  end,
})

-- Keep an OPEN Diffview's file panel live: refresh it when the working tree
-- changes — your saves, or files an agent rewrote on disk (which the auto-reload
-- above pulls in). Cheap no-op unless diffview is loaded with a view open.
local function refresh_diffview()
  if not package.loaded["diffview"] then return end
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.get_current_view and lib.get_current_view() then
    pcall(vim.cmd, "DiffviewRefresh")
  end
end
vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost", "FocusGained" }, {
  group = aug,
  callback = function() vim.schedule(refresh_diffview) end,
})

-- :DiffOrig — diff the current buffer against its on-disk version (what an agent
-- changed vs what you have). Built-in diff mode, no plugin. :diffoff! to exit.
vim.api.nvim_create_user_command("DiffOrig", function()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or vim.fn.filereadable(path) == 0 then
    vim.notify("DiffOrig: current buffer has no file on disk", vim.log.levels.WARN)
    return
  end
  local ft = vim.bo.filetype
  vim.cmd("diffthis")
  vim.cmd("vertical new")
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.filetype = ft
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn.readfile(path)) -- the on-disk version
  vim.cmd("diffthis")
end, { desc = "Diff buffer against the file on disk" })

-- ---------------------------------------------------------------------------
-- Big-file guard: drop expensive features on files > 1 MB for fast loading.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("BufReadPre", {
  group = aug,
  callback = function(args)
    local name = vim.api.nvim_buf_get_name(args.buf)
    local ok, stats = pcall(vim.uv.fs_stat, name)
    if ok and stats and stats.size > 1024 * 1024 then
      vim.b[args.buf].large_file = true
      vim.opt_local.swapfile = false
      vim.opt_local.undofile = false
      vim.opt_local.foldmethod = "manual"
      vim.opt_local.spell = false
      vim.cmd("syntax clear")
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Colors: keep the UI fully transparent for ANY colorscheme by stripping
-- backgrounds on every ColorScheme event. The palette itself comes from the
-- active scheme — the bundled "teal" scheme (colors/teal.lua) by default, or
-- anything you add to vim.pack and pick with <leader>uc.
-- ---------------------------------------------------------------------------
local function transparent()
  for _, g in ipairs({
    "Normal", "NormalNC", "NormalFloat", "FloatBorder", "FloatTitle",
    "SignColumn", "LineNr", "CursorLineNr", "FoldColumn", "EndOfBuffer",
    "MsgArea", "MsgSeparator", "WinSeparator", "VertSplit",
    "StatusLine", "StatusLineNC", "TabLine", "TabLineFill",
    "Pmenu", "PmenuSbar", "WinBar", "WinBarNC",
  }) do
    local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
    hl.bg, hl.ctermbg = nil, nil
    vim.api.nvim_set_hl(0, g, hl)
  end
  -- Statusline text must stay readable once its background is stripped: some
  -- schemes (e.g. dank) give the active StatusLine a dark fg meant for a light
  -- bar, which vanishes on the transparent (dark) terminal. Pin readable fgs.
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "StatusLine", { fg = normal.fg, bold = true })
  vim.api.nvim_set_hl(0, "StatusLineNC", { fg = comment.fg or normal.fg })
end

vim.api.nvim_create_autocmd("ColorScheme", { group = aug, callback = transparent })
-- Persisted colorscheme: remembered across restarts AND config updates. The
-- choice lives in the STATE dir (outside the git-tracked config), so an
-- installer `git pull` never touches it. Saved on exit, so <leader>uc and
-- :colorscheme both stick. Defaults to dank (which itself → teal without DMS).
local theme_file = vim.fn.stdpath("state") .. "/colorscheme"
local function read_theme()
  local ok, lines = pcall(vim.fn.readfile, theme_file)
  if ok and lines[1] and lines[1] ~= "" then return lines[1] end
  return "dank"
end
if not pcall(vim.cmd.colorscheme, read_theme()) then pcall(vim.cmd.colorscheme, "teal") end
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = aug,
  callback = function()
    if vim.g.colors_name then pcall(vim.fn.writefile, { vim.g.colors_name }, theme_file) end
  end,
})

-- ---------------------------------------------------------------------------
-- Hot-reload: re-source init.lua when it changes — saved inside Neovim
-- (BufWritePost) OR edited by another process (libuv fs_event), so external
-- edits apply without :source. Debounced because one save can fire both
-- triggers; _G state survives the re-source so watchers never stack.
-- ---------------------------------------------------------------------------
local config_file = vim.fn.stdpath("config") .. "/init.lua"

local function reload_config()
  local now = vim.uv.now()
  if _G.__last_reload and now - _G.__last_reload < 200 then return end
  _G.__last_reload = now
  local ok, err = pcall(vim.cmd.source, vim.fn.fnameescape(config_file))
  vim.notify(
    ok and "init.lua reloaded" or ("init.lua reload failed: " .. tostring(err)),
    ok and vim.log.levels.INFO or vim.log.levels.ERROR
  )
end

vim.api.nvim_create_autocmd("BufWritePost", {
  group = aug,
  pattern = config_file,
  callback = reload_config,
})

-- External-edit watcher. Re-armed by the re-source above, because editors
-- replace the file atomically and the watched inode goes stale after a write.
if _G.__cfg_watch then pcall(function() _G.__cfg_watch:stop() end) end
_G.__cfg_watch = vim.uv.new_fs_event()
if _G.__cfg_watch then
  _G.__cfg_watch:start(config_file, {}, vim.schedule_wrap(function(err)
    if not err then reload_config() end
  end))
end
