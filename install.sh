#!/usr/bin/env bash
# ============================================================================
# install.sh — set up this Neovim config on Linux or macOS.
#
#   * installs deps: Neovim >= 0.12, ripgrep, fd, fzf, git, a C compiler, uv
#   * installs the Python LSPs ty + ruff via uv
#   * pulls the config into ~/.config/nvim (git clone, or git pull if present)
#   * pre-installs plugins (vim.pack) and compiles Treesitter parsers
#
# Usage:
#   ./install.sh                         # from a clone, or…
#   curl -fsSL https://raw.githubusercontent.com/lucianosrp/nvim/main/install.sh | bash
#
# Override the source repo with NVIM_CONFIG_REPO=<url> ./install.sh
# Safe to re-run (idempotent); backs up any existing non-git ~/.config/nvim.
# ============================================================================
set -euo pipefail

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/lucianosrp/nvim.git}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
NVIM_MIN="0.12"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
[ "$(id -u)" -ne 0 ] && have sudo && SUDO="sudo"

NO_ANIM=0
for a in "$@"; do [ "$a" = "--no-anim" ] && NO_ANIM=1; done

# A tiny send-off animation. Disable with --no-anim; auto-skipped when stdout
# isn't a terminal (so piped/CI logs stay clean).
play_anim() {
  [ "$NO_ANIM" = 1 ] && return 0
  [ -t 1 ] || return 0
  _anim_render   # shared with the demo / install
}
# Rocket + colored braille exhaust flying through a twinkling starfield.
_anim_render() {
  local R='\033[0m'
  local smoke=('⠁' '⠂' '⠄' '⡀' '⢀' '⠠' '⣀' '⣄' '⣤' '⣦' '⣶' '⣷' '⣿') ns=13
  local stch=('✦' '✧' '⋆' '·' '✫') stcol=('\033[93m' '\033[96m' '\033[97m' '\033[95m' '\033[94m')
  local w=52 pos col d frame=0 line k
  printf '\n'
  for ((pos = 3; pos <= w; pos += 2)); do
    line=''
    for ((col = 0; col < w; col++)); do
      if ((col == pos)); then line+="\033[1;96m▶${R}"            # nose
      elif ((col == pos - 1)); then line+="\033[1;97m=${R}"       # body
      elif ((col == pos - 2)); then line+="\033[1;93m}${R}"       # engine
      elif ((col < pos - 2)); then
        d=$((pos - 2 - col))
        if ((d <= ns)); then
          local ch="${smoke[ns - d]}"
          if ((d <= 2)); then line+="\033[93m${ch}${R}"           # flame
          elif ((d <= 4)); then line+="\033[33m${ch}${R}"         # orange
          elif ((d <= 6)); then line+="\033[91m${ch}${R}"         # ember
          elif ((d <= 9)); then line+="\033[90m${ch}${R}"         # smoke
          else line+="\033[2;90m${ch}${R}"; fi                    # wisp
        else line+=' '; fi
      elif (((col * 7 + 3) % 11 == 0)); then                      # twinkling star ahead
        k=$(((frame + col) % 5)); line+="${stcol[k]}${stch[k]}${R}"
      else line+=' '; fi
    done
    printf '\r  %b' "$line"
    frame=$((frame + 1))
    sleep 0.012 || true
  done
  printf '\r\033[K  \033[93m✦\033[0m \033[96m✧\033[0m \033[95m⋆\033[0m  \033[1;92mblast off — nvim is ready!\033[0m  \033[2m(<Space>k for keys)\033[0m  \033[95m⋆\033[0m \033[96m✧\033[0m \033[93m✦\033[0m\n\n'
}

# ---------------------------------------------------------------------------
# 1. Detect platform + package manager
# ---------------------------------------------------------------------------
OS="$(uname -s)"
PM=""
case "$OS" in
  Darwin) PM="brew" ;;
  Linux)
    for pm in pacman apt-get dnf zypper apk xbps-install; do
      have "$pm" && PM="$pm" && break
    done
    ;;
  *) die "Unsupported OS: $OS (this script covers Linux + macOS; Windows: use install.ps1)." ;;
esac
[ -n "$PM" ] || die "No supported package manager found (pacman/apt/dnf/zypper/apk/xbps/brew)."
info "Platform: $OS  ·  package manager: $PM"

# ---------------------------------------------------------------------------
# 2. System dependencies. Neovim is handled separately (apt ships an old one),
#    and fd is best-effort (the config falls back to ripgrep if it's missing).
# ---------------------------------------------------------------------------
info "Installing system packages…"
case "$PM" in
  brew)         brew install neovim ripgrep fd fzf git curl || true ;;
  pacman)       $SUDO pacman -S --needed --noconfirm neovim ripgrep fd fzf git gcc curl ;;
  apt-get)      $SUDO apt-get update -y
                $SUDO apt-get install -y ripgrep fd-find fzf git build-essential curl ;;
  dnf)          $SUDO dnf install -y neovim ripgrep fd-find fzf git gcc curl ;;
  zypper)       $SUDO zypper --non-interactive install neovim ripgrep fd fzf git gcc curl ;;
  apk)          $SUDO apk add neovim ripgrep fd fzf git build-base curl ;;
  xbps-install) $SUDO xbps-install -Sy neovim ripgrep fd fzf git gcc curl ;;
esac

# ---------------------------------------------------------------------------
# 3. Ensure Neovim >= 0.12 — fall back to the official prebuilt if the distro's
#    is too old (or absent, e.g. Debian/Ubuntu).
# ---------------------------------------------------------------------------
nvim_ok() {
  have nvim || return 1
  local v
  v="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  [ -n "$v" ] && [ "$(printf '%s\n%s\n' "$NVIM_MIN" "$v" | sort -V | head -1)" = "$NVIM_MIN" ]
}
if ! nvim_ok; then
  info "Installing Neovim >= $NVIM_MIN from the official release…"
  case "$OS-$(uname -m)" in
    Linux-x86_64)  TGZ="nvim-linux-x86_64.tar.gz" ;;
    Linux-aarch64) TGZ="nvim-linux-arm64.tar.gz" ;;
    Darwin-arm64)  TGZ="nvim-macos-arm64.tar.gz" ;;
    Darwin-x86_64) TGZ="nvim-macos-x86_64.tar.gz" ;;
    *) die "No prebuilt Neovim for $OS-$(uname -m); please build from source (needs glibc >= 2.31 on Linux)." ;;
  esac
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$TGZ" -o "/tmp/$TGZ" \
    || die "Failed to download $TGZ"
  tar -xzf "/tmp/$TGZ" -C "$HOME/.local" --strip-components=1
  export PATH="$HOME/.local/bin:$PATH"
  case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) warn "Add \$HOME/.local/bin to your PATH." ;; esac
fi
nvim_ok || die "Neovim >= $NVIM_MIN is still not available on PATH."
info "Neovim $(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) OK."

# ---------------------------------------------------------------------------
# 4. uv + Python LSPs (ty type-checker, ruff linter/formatter)
# ---------------------------------------------------------------------------
if ! have uv; then
  info "Installing uv…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
info "Installing ty + ruff via uv…"
uv tool install ty   >/dev/null 2>&1 || uv tool upgrade ty   || warn "ty install failed (Python LSP type-check unavailable)"
uv tool install ruff >/dev/null 2>&1 || uv tool upgrade ruff || warn "ruff install failed (Python lint/format unavailable)"

# ---------------------------------------------------------------------------
# 5. Fetch the config into ~/.config/nvim
# ---------------------------------------------------------------------------
if [ -d "$CONFIG_DIR/.git" ]; then
  info "Updating existing config in $CONFIG_DIR…"
  git -C "$CONFIG_DIR" pull --ff-only || warn "git pull failed; leaving $CONFIG_DIR as-is."
else
  if [ -e "$CONFIG_DIR" ]; then
    BAK="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
    warn "Backing up existing $CONFIG_DIR -> $BAK"
    mv "$CONFIG_DIR" "$BAK"
  fi
  info "Cloning $REPO_URL -> $CONFIG_DIR…"
  git clone --depth 1 "$REPO_URL" "$CONFIG_DIR"
fi

# ---------------------------------------------------------------------------
# 6. Pre-install plugins + compile parsers so the first real launch is instant
# ---------------------------------------------------------------------------
info "Installing plugins (vim.pack)…"
nvim --headless "+qa" >/dev/null 2>&1 || true
info "Compiling Treesitter parsers (needs a C compiler, ~1-2 min)…"
nvim --headless \
  -c 'silent! TSInstallSync! python lua vim vimdoc bash json yaml toml markdown markdown_inline' \
  -c 'qa' >/dev/null 2>&1 || true

printf '\033[1m%s\033[0m\n' "Done. Launch 'nvim'."
play_anim
