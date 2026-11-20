# Default file finders — exclude heavy trees (node_modules, build outputs)
# so Ctrl+T / Telescope don't scan gigabytes. fd is fastest; fallback to rg.
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --exclude node_modules --exclude .next --exclude dist --exclude build --exclude target --exclude .venv --exclude .cache 2>/dev/null'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git --exclude node_modules --exclude .next 2>/dev/null'
elif command -v rg >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/*" --glob "!node_modules/*" --glob "!.next/*" --glob "!target/*" 2>/dev/null'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# Key bindings and completion come from the fzf binary itself (mise installs
# it). Cached like starship and atuin in core.zsh, so a shell start does not
# fork fzf; delete the cache file after an fzf upgrade.
if command -v fzf >/dev/null 2>&1; then
  _dotfiles_fzf_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/fzf.zsh"
  if [[ ! -f "$_dotfiles_fzf_cache" ]]; then
    mkdir -p "${_dotfiles_fzf_cache:h}"
    fzf --zsh > "$_dotfiles_fzf_cache" 2>/dev/null
  fi
  [[ -f "$_dotfiles_fzf_cache" ]] && source "$_dotfiles_fzf_cache"
  unset _dotfiles_fzf_cache
fi
