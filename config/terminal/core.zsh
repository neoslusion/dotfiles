# Dotfiles Core Configuration
# This file is sourced by ~/.zshrc or ~/.bashrc

# --- ENVIRONMENT DETECTION ---
is-macos() { [[ "$OSTYPE" == "darwin"* ]]; }
is-linux() { [[ "$OSTYPE" == "linux"* ]]; }
is-wsl() { [[ -n "$WSL_DISTRO_NAME" || -n "$WSL_INTEROP" ]]; }
is-termux() { [[ "$PREFIX" == *"/com.termux/"* ]]; }

# --- PATH MANAGEMENT ---
path_remove() {
  PATH=":${PATH}:"
  PATH="${PATH//:$1:/:}"
  PATH="${PATH#:}"
  PATH="${PATH%:}"
}

path_add() {
  path_remove "$1"
  [[ -d "$1" ]] && export PATH="$1:$PATH"
}

# --- SYSTEM ENVIRONMENT ---
# Load system environment (Proxies, etc.)
if [[ -f /etc/environment ]]; then
  # Parse manually to avoid recursive PATH expansion issues if /etc/environment contains $PATH
  while IFS='=' read -r key val; do
    [[ -z "$key" || "$key" == "#"* || "$key" == "PATH" ]] && continue
    val="${val%\"}"
    val="${val#\"}"
    val="${val%\'}"
    val="${val#\'}"
    export "$key"="$val"
  done < /etc/environment
fi

# --- MACHINE-LOCAL SECRETS ---
# API keys etc. live outside the repo (scaffolded by install_configs.sh).
[[ -f "$HOME/.secrets/env.sh" ]] && source "$HOME/.secrets/env.sh"

# Standard PATHs
path_add "$HOME/bin"
export PATH="$PATH:$HOME/.local/bin"
path_add "$HOME/.atuin/bin"
path_add "/usr/local/bin"
path_add "/opt/nvim"

# Add Homebrew to path if it exists
if is-macos; then
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

# --- FIX: TRUE COLOR PROPAGATION ---
export COLORTERM=truecolor

# Starship dirty check spawns `git status` on every prompt (760ms on NTFS,
# ~90ms over WSL 9P). Windows profile already sets STARSHIP_GIT_DIRTY_SKIP=1
# to skip it; do the same for WSL where it hurts most. Native Linux keeps
# the ✗ indicator (cheap there) unless you export DOTFILES_STARSHIP_DIRTY=0.
if is-wsl; then
  export STARSHIP_GIT_DIRTY_SKIP=1
elif [[ "${DOTFILES_STARSHIP_DIRTY:-1}" == "0" ]]; then
  export STARSHIP_GIT_DIRTY_SKIP=1
fi

# WSL Home Normalization
if is-wsl && [[ -n "$PS1" ]] && (( $+commands[wslpath] )); then
  _dotfiles_win_pwd="$(wslpath -w "$PWD" 2>/dev/null | tr -d '\r')"
  case "${_dotfiles_win_pwd:l}" in
    *'\windows\system32'|*'\windows\system32\'*) cd "$HOME" ;;
  esac
  unset _dotfiles_win_pwd
fi

# --- TOOL INITIALIZATION ---

# NVM
export NVM_DIR="$HOME/.nvm"
lazy_load_nvm() {
  unset -f nvm node npm npx
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
for cmd in nvm node npm npx; do
  eval "$cmd() { lazy_load_nvm; $cmd \"\$@\"; }"
done

# Expose the newest installed nvm node on PATH directly (cheap: no nvm.sh
# sourcing) so non-interactive children — Neovim -> Mason, LSP installers, etc. —
# can find node/npm. Interactive shells keep the lazy wrappers above, which are
# functions and so shadow this until first use (then load full nvm). Without
# this, `npm` is invisible to Neovim and Mason's npm-based servers never install.
_nvm_bin=$(command ls -d "$NVM_DIR"/versions/node/*/bin 2>/dev/null | sort -V | tail -1)
[ -n "$_nvm_bin" ] && export PATH="$_nvm_bin:$PATH"
unset _nvm_bin

# WSL: interop injects dozens of /mnt/c dirs into PATH, and every MISSED
# command lookup during init walks all of them over 9P (~90 ms per miss —
# zsh-vi-mode alone probes once). Shield plugin init; restored at the
# DYNAMIC PATH ADDITIONS section below, so the final PATH is unchanged.
_dotfiles_win_path=()
if is-wsl && [[ -n "$ZSH_VERSION" ]]; then
  for _p in $path; do [[ $_p == /mnt/* ]] && _dotfiles_win_path+=("$_p"); done
  path=(${path:#/mnt/*})
  unset _p
fi

# Oh My Zsh — tuned load: no updater check, no compaudit rescan, reused
# compdump. skip_global_compinit lives in ~/.zshenv (must run before
# /etc/zsh/zshrc, which fires a duplicate compinit otherwise).
export ZSH="$HOME/.oh-my-zsh"
zstyle ':omz:update' mode disabled
ZSH_DISABLE_COMPFIX=true
[[ -d "$HOME/.cache/zsh" ]] || mkdir -p "$HOME/.cache/zsh"
ZSH_COMPDUMP="$HOME/.cache/zsh/zcompdump-$ZSH_VERSION"
plugins=(zoxide zsh-vi-mode zsh-syntax-highlighting zsh-autosuggestions)
# Allow machine-specific plugins
[[ -n "$LOCAL_PLUGINS" ]] && plugins+=(${(z)LOCAL_PLUGINS})

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=1

# Source OMZ if zsh
if [[ -n "$ZSH_VERSION" && -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

# Starship — cached like windows/profile.ps1 (avoids fork per shell)
_dotfiles_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
if command -v starship >/dev/null 2>&1; then
  _dotfiles_starship_cache="$_dotfiles_cache_dir/starship.zsh"
  if [[ ! -f "$_dotfiles_starship_cache" ]]; then
    mkdir -p "$_dotfiles_cache_dir"
    starship init zsh > "$_dotfiles_starship_cache" 2>/dev/null
  fi
  [[ -f "$_dotfiles_starship_cache" ]] && source "$_dotfiles_starship_cache"
  unset _dotfiles_starship_cache
fi

# FZF + Atuin. Order matters twice over:
#  - fzf BEFORE atuin so atuin owns Ctrl+R (last-initialized wins);
#    fzf keeps Ctrl+T / Alt+C.
#  - zsh-vi-mode re-binds keys at the FIRST PROMPT, clobbering anything bound
#    at init time — so when zvm is loaded, defer both via
#    zvm_after_init_commands (the mechanism zvm provides for exactly this).
#  Atuin is also cached (like Starship) — `atuin init` forks per shell otherwise.
_dotfiles_init_pickers() {
  # zsh-vi-mode may invoke this after the startup scope has unset the shared
  # cache variable, so resolve the directory when the callback actually runs.
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
  [ -f ~/.config/zsh/fzf.zsh ] && source ~/.config/zsh/fzf.zsh
  if command -v atuin >/dev/null 2>&1; then
    _dotfiles_atuin_cache="$cache_dir/atuin.zsh"
    if [[ ! -f "$_dotfiles_atuin_cache" ]]; then
      mkdir -p "$cache_dir"
      atuin init zsh > "$_dotfiles_atuin_cache" 2>/dev/null
    fi
    [[ -f "$_dotfiles_atuin_cache" ]] && source "$_dotfiles_atuin_cache"
    unset _dotfiles_atuin_cache
  fi
}
if (( ${+functions[zvm_init]} )); then
  zvm_after_init_commands+=(_dotfiles_init_pickers)
else
  _dotfiles_init_pickers
fi
unset _dotfiles_cache_dir

# --- ALIASES & HELPERS ---

# Modern replacements
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons'
  alias ll='eza -l --icons'
  alias la='eza -la --icons'
  alias lt='eza --tree --icons'
fi

if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi

if command -v nvim >/dev/null 2>&1; then
  export EDITOR="nvim"
  export VISUAL="nvim"
fi

# bat: syntax-highlighted cat (parity with the pwsh profile's cat function).
# --paging=never: a cat replacement must never trap scripts in a pager.
if command -v bat >/dev/null 2>&1; then
  alias cat='bat -p --paging=never'
elif command -v batcat >/dev/null 2>&1; then   # Debian/Ubuntu binary name
  alias cat='batcat -p --paging=never'
fi

# Quick navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# --- WSL / WINDOWS BRIDGE ---
if is-wsl; then
  reveal() {
    local target="${1:-.}"
    if command -v explorer.exe >/dev/null 2>&1; then
      explorer.exe "$(wslpath -w "$target")" >/dev/null 2>&1
    fi
  }

  copy-path() {
    local target="${1:-$PWD}"
    if command -v clip.exe >/dev/null 2>&1; then
      wslpath -w "$target" | tr -d '\n' | clip.exe
    fi
  }
fi

# --- DYNAMIC PATH ADDITIONS ---
# Windows paths for WSL (must be set before tmux auto-start replaces the
# shell). Restore the interop dirs stripped before plugin init, then discover
# VS Code from Windows when its command is available. Windows dirs go at the
# END: each one costs a 9P stat on every lookup miss, and native binaries must
# win anyway.
if is-wsl && [[ -n "$ZSH_VERSION" ]]; then
  path+=($_dotfiles_win_path)
  unset _dotfiles_win_path
  if (( $+commands[where.exe] && $+commands[wslpath] )); then
    _dotfiles_code_cmd="$(where.exe code.cmd 2>/dev/null | head -n 1 | tr -d '\r')"
    if [[ -n "$_dotfiles_code_cmd" ]]; then
      _dotfiles_code_dir="$(dirname "$(wslpath -u "$_dotfiles_code_cmd")")"
      [[ -d "$_dotfiles_code_dir" ]] && path+=("$_dotfiles_code_dir")
    fi
    unset _dotfiles_code_cmd _dotfiles_code_dir
  fi
  typeset -U path  # dedup, first occurrence wins
fi

# --- TMUX AUTO-START (opt-in) ---
# herdr owns multiplexing now (Windows-native, hjkl chords in profile/keys);
# tmux stays installed for SSH boxes and manual use. Set DOTFILES_TMUX=1 to
# restore the auto-attached Main session; NO_TMUX=1 still force-skips.
should_autostart_tmux() {
  [[ -n "$TMUX" ]] && return 1
  [[ -z "$PS1" ]] && return 1
  [[ ! -t 0 || ! -t 1 ]] && return 1
  [[ "$TERM" == "dumb" ]] && return 1
  [[ "$TERM_PROGRAM" == "vscode" ]] && return 1
  [[ -n "$VSCODE_IPC_HOOK_CLI" ]] && return 1
  [[ -n "$SSH_CONNECTION" || -n "$CI" ]] && return 1
  [[ -n "$NO_TMUX" ]] && return 1
  command -v tmux >/dev/null 2>&1
}

if [[ -n "$ZSH_VERSION" ]] && [[ -n "$DOTFILES_TMUX" ]] && should_autostart_tmux; then
  tmux new-session -A -s Main
fi
