# ============================================================================
# install.ps1 — set up this Neovim config on Windows (PowerShell 5+).
#
#   * installs deps: Neovim, ripgrep, fd, fzf, git, uv  (via winget or scoop)
#   * installs the Python LSPs ty + ruff via uv
#   * pulls the config into %LOCALAPPDATA%\nvim (git clone, or pull if present)
#   * pre-installs plugins (vim.pack) and compiles Treesitter parsers
#
# Usage (from a PowerShell prompt):
#   irm https://raw.githubusercontent.com/lucianosrp/nvim/main/install.ps1 | iex
#   # or, from a clone:  .\install.ps1
#
# Override the source repo with:  $env:NVIM_CONFIG_REPO = "<url>"
# Note: compiling Treesitter parsers needs a C compiler on PATH (zig, or the
#       MSVC Build Tools). Without one, syntax still works via plugin parsers.
# ============================================================================
$ErrorActionPreference = "Stop"

$RepoUrl   = if ($env:NVIM_CONFIG_REPO) { $env:NVIM_CONFIG_REPO } else { "https://github.com/lucianosrp/nvim.git" }
$ConfigDir = Join-Path $env:LOCALAPPDATA "nvim"

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Info($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "!! $msg"  -ForegroundColor Yellow }

# A tiny send-off animation. Disable with --no-anim (or $env:NVIM_NO_ANIM=1);
# auto-skipped when output is redirected.
$NoAnim = ($args -contains '--no-anim') -or [bool]$env:NVIM_NO_ANIM
function Play-Anim {
  if ($NoAnim) { return }
  if ([Console]::IsOutputRedirected) { return }
  $w = 44
  Write-Host ""
  for ($pos = 0; $pos -le $w; $pos += 2) {
    Write-Host -NoNewline ("`r  " + ('.' * $pos) + "}==>")
    Start-Sleep -Milliseconds 30
  }
  Write-Host -NoNewline ("`r" + (' ' * ($w + 8)) + "`r")
  Write-Host "  *  blast off - nvim is ready!  (<Space>k for keys)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 1. System dependencies via winget (preferred) or scoop
# ---------------------------------------------------------------------------
if (Have winget) {
  Info "Installing dependencies via winget…"
  $pkgs = @(
    "Neovim.Neovim", "BurntSushi.ripgrep.MSVC", "sharkdp.fd",
    "junegunn.fzf", "Git.Git", "astral-sh.uv"
  )
  foreach ($p in $pkgs) {
    winget install --silent --accept-package-agreements --accept-source-agreements -e --id $p
  }
} elseif (Have scoop) {
  Info "Installing dependencies via scoop…"
  scoop install neovim ripgrep fd fzf git uv
} else {
  throw "Install winget (Windows 10/11) or scoop first, then re-run."
}

# Refresh PATH for this session so freshly-installed tools are found
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path","User")

# ---------------------------------------------------------------------------
# 2. Python LSPs (ty type-checker, ruff linter/formatter)
# ---------------------------------------------------------------------------
if (Have uv) {
  Info "Installing ty + ruff via uv…"
  try { uv tool install ty }   catch { uv tool upgrade ty }
  try { uv tool install ruff } catch { uv tool upgrade ruff }
} else {
  Warn "uv not found on PATH after install — skipping ty/ruff. Re-open the shell and run: uv tool install ty ruff"
}

# ---------------------------------------------------------------------------
# 3. Fetch the config into %LOCALAPPDATA%\nvim
# ---------------------------------------------------------------------------
if (Test-Path (Join-Path $ConfigDir ".git")) {
  Info "Updating existing config in $ConfigDir…"
  git -C $ConfigDir pull --ff-only
} else {
  if (Test-Path $ConfigDir) {
    $bak = "$ConfigDir.bak." + (Get-Date -Format "yyyyMMddHHmmss")
    Warn "Backing up existing $ConfigDir -> $bak"
    Move-Item $ConfigDir $bak
  }
  Info "Cloning $RepoUrl -> $ConfigDir…"
  git clone --depth 1 $RepoUrl $ConfigDir
}

# ---------------------------------------------------------------------------
# 4. Pre-install plugins + compile parsers
# ---------------------------------------------------------------------------
Info "Installing plugins (vim.pack)…"
nvim --headless "+qa"
Info "Compiling Treesitter parsers (needs a C compiler; skipped silently if absent)…"
nvim --headless -c "silent! TSInstallSync! python lua vim vimdoc bash json yaml toml markdown markdown_inline" -c "qa"

Write-Host "Done. Launch 'nvim'." -ForegroundColor Green
Play-Anim
