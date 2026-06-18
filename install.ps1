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
  $e = [char]27
  $heavy = @('⣿','⣷','⣾','⣶','⣦','⣟','⣯','⣽')   # dense, near the engine
  $mid   = @('⠿','⠷','⠾','⠶','⡶','⢾','⣀','⣄')   # billowing smoke
  $light = @('⠁','⠂','⠄','⠈','⠐','⠠','⡀','⢀')   # dissipating wisps
  $flame = @('93','33','91')                       # flicker: yellow/orange/red
  $stch = @('✦','✧','⋆','·','✫'); $stcol = @('93','96','97','95','94')
  $w = 54; $frame = 0
  Write-Host ""
  for ($pos = 3; $pos -le $w; $pos += 2) {
    $line = ''
    for ($col = 0; $col -lt $w; $col++) {
      if ($col -eq $pos) { $line += "$e[1;96m▶$e[0m" }
      elseif ($col -eq $pos - 1) { $line += "$e[1;97m=$e[0m" }
      elseif ($col -eq $pos - 2) { $line += "$e[$($flame[(Get-Random -Max 3)])m}$e[0m" }
      elseif ($col -lt $pos - 2) {
        $d = $pos - 2 - $col; $r = Get-Random -Maximum 100
        if ($d -le 3) { $line += "$e[$($flame[(Get-Random -Max 3)])m$($heavy[(Get-Random -Max 8)])$e[0m" }
        elseif ($d -le 7)  { if ($r -lt 22) { $line += ' ' } else { $line += "$e[90m$($mid[(Get-Random -Max 8)])$e[0m" } }
        elseif ($d -le 13) { if ($r -lt 58) { $line += ' ' } else { $line += "$e[2;90m$($light[(Get-Random -Max 8)])$e[0m" } }
        else { $line += ' ' }
      }
      elseif ((($col * 5 + $frame) % 9) -eq 0) {
        $r = Get-Random -Maximum 5
        $line += "$e[$($stcol[$r])m$($stch[$r])$e[0m"
      } else { $line += ' ' }
    }
    Write-Host -NoNewline ("`r$e[K  $line")
    $frame++
    Start-Sleep -Milliseconds 18
  }
  Write-Host -NoNewline ("`r$e[K")
  Write-Host "  $e[93m✦$e[0m $e[96m✧$e[0m  blast off - nvim is ready!  (<Space>k for keys)  $e[95m⋆$e[0m"
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
  # Preserve any local edits across the update: stash -> pull -> pop.
  $stashed = $false
  git -C $ConfigDir diff --quiet HEAD 2>$null
  if ($LASTEXITCODE -ne 0) {
    git -C $ConfigDir stash push -u -m "install.ps1 pre-update" | Out-Null
    if ($LASTEXITCODE -eq 0) { $stashed = $true; Info "Stashed your local edits." }
  }
  git -C $ConfigDir pull --ff-only
  if ($stashed) {
    git -C $ConfigDir stash pop
    if ($LASTEXITCODE -ne 0) { Warn "Your edits are safe in 'git stash' - reapply: git -C $ConfigDir stash pop" }
    else { Info "Re-applied your local edits." }
  }
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
