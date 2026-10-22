#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

CONFIG_DIR="$HOME/.config"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_CONFIG_DIR="$REPO_ROOT/config"

log "Config source: $REPO_CONFIG_DIR"
log "Config destination: $CONFIG_DIR"

mkdir -p "$CONFIG_DIR"

# Helper function to copy config folders/files
# Handles the case where destination exists as file but source is a directory (or vice versa)
copy_config() {
    local name=$1
    local dest="${2:-$CONFIG_DIR/$name}"

    if [ ! -e "$REPO_CONFIG_DIR/$name" ]; then
        warning "copy_config: source '$name' not found in $REPO_CONFIG_DIR — skipping"
        return 1
    fi

    # Unchanged: leave it alone, so a re-run neither rewrites it nor replaces
    # the last real backup with a copy of identical content.
    if diff -rq "$REPO_CONFIG_DIR/$name" "$dest" >/dev/null 2>&1; then
        return 0
    fi

    if [ -e "$dest" ]; then
        rm -rf "${dest}.bak"
        mv "$dest" "${dest}.bak"
    fi

    if [ -d "$REPO_CONFIG_DIR/$name" ]; then
        # Source is a directory: ensure destination is also a directory
        mkdir -p "$dest"
        cp -R "$REPO_CONFIG_DIR/$name/." "$dest/"
    elif [ -f "$REPO_CONFIG_DIR/$name" ]; then
        # Source is a single file: copy it directly
        local dest_dir
        dest_dir="$(dirname "$dest")"
        mkdir -p "$dest_dir"
        cp -f "$REPO_CONFIG_DIR/$name" "$dest"
    fi
}

# Helper to safely source a file without overwriting
inject_sourcing() {
    local target=$1
    local source_line=$2
    local label=$3

    if [ ! -f "$target" ]; then
        echo "$source_line" > "$target"
        success "Created $label"
    elif ! grep -qF "$source_line" "$target"; then
        echo -e "\n# Added by dotfiles\n$source_line" >> "$target"
        success "Injected sourcing into $label"
    else
        skip_step "$label" "already sourced"
    fi
}

install_shell_configs() {
    # 1. Deploy core configuration to ~/.config/zsh/
    mkdir -p "$CONFIG_DIR/zsh"
    cp -f "$REPO_CONFIG_DIR/terminal/core.zsh" "$CONFIG_DIR/zsh/core.zsh"
    cp -f "$REPO_CONFIG_DIR/terminal/.fzf.zsh" "$CONFIG_DIR/zsh/fzf.zsh"
    
    # 2. Deploy ~/.zshrc bootstrap (overwrites OMZ default) + ~/.zshenv
    # (skip_global_compinit must run before /etc/zsh/zshrc)
    cp -f "$REPO_CONFIG_DIR/terminal/.zshrc" "$HOME/.zshrc"
    cp -f "$REPO_CONFIG_DIR/terminal/.zshenv" "$HOME/.zshenv"
    success "Deployed .zshrc bootstrap"

    # 3. Handle .zprofile similarly
    cp -f "$REPO_CONFIG_DIR/terminal/.zprofile" "$CONFIG_DIR/zsh/zprofile.zsh"
    local zprofile_bootstrap='[[ -f "$HOME/.config/zsh/zprofile.zsh" ]] && source "$HOME/.config/zsh/zprofile.zsh"'
    inject_sourcing "$HOME/.zprofile" "$zprofile_bootstrap" ".zprofile bootstrap"
    
    # Starship is global
    cp -f "$REPO_CONFIG_DIR/terminal/starship.toml" "$CONFIG_DIR/starship.toml"
}

install_scripts() {
    # Legacy launcher removed; clean up stale copies from older installs
    local legacy_launcher="rice"

    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/.local/bin/utils"
    rm -f "$HOME/.local/bin/$legacy_launcher" "$HOME/.local/bin/sessionizer" \
        "$HOME/.local/bin/tmux-status"

    # Runtime helpers installed into ~/.local/bin (one list, one copy+chmod).
    local script
    for script in audit-nvim-keymaps sys-info dotsync; do
        cp -f "$REPO_ROOT/scripts/$script" "$HOME/.local/bin/$script"
        chmod +x "$HOME/.local/bin/$script"
    done

    # Non-executable files that must sit next to their entry points
    cp -f "$REPO_ROOT/scripts/audit_nvim_keymaps.py" "$HOME/.local/bin/audit_nvim_keymaps.py"
    cp -f "$REPO_ROOT/scripts/utils/env.sh" "$HOME/.local/bin/utils/env.sh"
    cp -f "$REPO_ROOT/scripts/utils/paths.sh" "$HOME/.local/bin/utils/paths.sh"
}

install_tmux_config() {
    mkdir -p "$CONFIG_DIR/tmux"
    cp -rf "$REPO_CONFIG_DIR/tmux/"* "$CONFIG_DIR/tmux/"
    cp -f "$REPO_CONFIG_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
    rm -f "$CONFIG_DIR/tmux/theme.conf"
    cp -f "$CONFIG_DIR/tmux/themes/dotbar.conf" "$CONFIG_DIR/tmux/theme.conf"
}

install_shell_speedup() {
    # Byte-compile Oh My Zsh libs and plugins: zsh loads .zwc wordcode
    # instead of re-parsing source on every shell start. Idempotent; any
    # .zwc can be deleted safely (regenerated on the next run; zsh falls
    # back to the source when the .zwc is stale). No-op without OMZ.
    [ -d "$HOME/.oh-my-zsh" ] || return 0
    command -v zsh >/dev/null 2>&1 || return 0
    zsh -c '
        setopt null_glob
        for f in "$HOME"/.oh-my-zsh/oh-my-zsh.sh \
                 "$HOME"/.oh-my-zsh/lib/*.zsh \
                 "$HOME"/.oh-my-zsh/plugins/*/*.plugin.zsh \
                 "$HOME"/.oh-my-zsh/custom/plugins/*/*.zsh; do
            [[ -f "$f.zwc" && "$f.zwc" -nt "$f" ]] || zcompile "$f" 2>/dev/null
        done
        return 0'
}

# BSD sed (macOS) has no suffix-less -i, and -i.bak would clobber the
# settings.json.bak user backups, so render through a temp file instead.
render_token() { # render_token <file> <token> <value>
    sed "s|$2|$3|g" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# First-party Claude Code mods (config/claude/mods) are a folder marketplace.
# Listing them in settings.json does not install them, so every run registers
# them through the CLI (marketplace add and install are both idempotent). Do not
# set CLAUDE_CONFIG_DIR here, even to ~/.claude: the CLI then looks for its
# global config at ~/.claude/.claude.json instead of ~/.claude.json, warns, and
# creates a stray one.
deploy_claude_mods() {
    copy_config claude/mods "$HOME/.claude/mods"
    if ! command -v claude >/dev/null 2>&1; then
        warning "claude not on PATH: mods copied to ~/.claude/mods but not registered"
        return 0
    fi
    # Git Bash: the Windows claude CLI keeps its registry under USERPROFILE,
    # not HOME. With HOME redirected (a test or temp-home run) it would point
    # the real registry at this HOME, and the mods break once it is deleted.
    if [ -n "${USERPROFILE:-}" ] && command -v cygpath >/dev/null 2>&1 \
        && [ "$(cygpath -u "$USERPROFILE")" != "$HOME" ]; then
        warning "claude CLI home is not \$HOME: mods copied but not registered"
        return 0
    fi
    local mod
    claude plugin marketplace add "$HOME/.claude/mods" >/dev/null \
        || { warning "claude mods: marketplace registration failed"; return 0; }
    for mod in "$HOME/.claude/mods"/*/.claude-plugin/plugin.json; do
        mod="$(basename "$(dirname "$(dirname "$mod")")")"
        claude plugin install "$mod@my-mods" --scope user >/dev/null \
            || warning "claude mods: install of $mod failed"
    done
}

install_agent_configs() {
    # Claude Code / Codex seeds. File-level copies ONLY — never replace the
    # whole ~/.claude or ~/.codex dir (they hold live sessions, history,
    # plugins, credentials). Secrets are NOT deployed from the repo: Claude and
    # Codex API profiles load their machine-local files only on demand.

    # Shared engineering guidance (config/agents): ENGINEERING.md copied
    # verbatim to every agent home.
    deploy_shared_agent_docs() {
        local dest="$1"
        cp -f "$REPO_CONFIG_DIR/agents/ENGINEERING.md" "$dest/ENGINEERING.md"
    }

    # Merge a rendered repo settings file into a live one that other writers
    # share (see merge_settings.py), then drop the rendered copy.
    merge_agent_settings() {
        local rendered="$1" live="$2"
        if command -v python3 >/dev/null 2>&1; then
            python3 "$SCRIPT_DIR/merge_settings.py" "$rendered" "$live" \
                || warning "$live merge failed; file left as it was"
        elif [ ! -f "$live" ]; then
            cp -f "$rendered" "$live"
        else
            # Never fall back to overwriting: that is what drops the other entries.
            warning "python3 not found: $live left unmerged"
        fi
        rm -f "$rendered"
    }

    # Claude Code
    mkdir -p "$HOME/.claude"
    cp -f "$REPO_CONFIG_DIR/claude/statusline.py" "$HOME/.claude/statusline.py"
    # Statusline commands get absolute paths: agents run them through a
    # non-interactive shell that may not have the interactive PATH.
    local python_path rendered
    python_path="$(command -v python3 || echo python3)"
    rendered="$(mktemp)"
    cp -f "$REPO_CONFIG_DIR/claude/settings.json" "$rendered"
    render_token "$rendered" __PYTHON__ "$python_path"
    render_token "$rendered" __CLAUDE_STATUSLINE__ "$HOME/.claude/statusline.py"
    # settings.json and CLAUDE.md are shared with other installers (e.g. rtk)
    # and with /plugin and /effort, so merge into them instead of replacing
    # them: everyone else's entries survive a refresh.
    merge_agent_settings "$rendered" "$HOME/.claude/settings.json"
    deploy_claude_mods
    inject_sourcing "$HOME/.claude/CLAUDE.md" "@ENGINEERING.md" "Claude CLAUDE.md"
    deploy_shared_agent_docs "$HOME/.claude"

    # Codex: config.toml is seed-if-missing ONLY — Codex appends project
    # trust entries at runtime; overwriting would wipe them.
    mkdir -p "$HOME/.codex"
    # Ensured, not copied: rtk adds its own import line to this file.
    inject_sourcing "$HOME/.codex/AGENTS.md" "@~/.codex/ENGINEERING.md" "Codex AGENTS.md"
    deploy_shared_agent_docs "$HOME/.codex"
    if [ ! -f "$HOME/.codex/config.toml" ]; then
        cp "$REPO_CONFIG_DIR/codex/config.toml" "$HOME/.codex/config.toml"
    fi

    # Antigravity (AGY)
    local agy_dir="$HOME/.gemini/antigravity-cli"
    mkdir -p "$agy_dir"
    cp -f "$REPO_CONFIG_DIR/antigravity/AGENTS.md" "$agy_dir/AGENTS.md"
    deploy_shared_agent_docs "$agy_dir"
    cp -f "$REPO_CONFIG_DIR/antigravity/statusline.py" "$agy_dir/statusline.py"
    # Antigravity writes its own keys (model, trusted workspaces) into
    # settings.json, so merge the repo's statusLine in rather than seeding it
    # once: a refresh also repoints a stale interpreter path.
    rendered="$(mktemp)"
    cp -f "$REPO_CONFIG_DIR/antigravity/settings.json" "$rendered"
    # Unquoted: Antigravity runs the command through cmd on Windows, which
    # receives quotes as an escaped pair and then cannot find the program.
    case "$python_path$agy_dir" in *" "*)
        warning "Antigravity statusline command cannot quote a path with a space" ;;
    esac
    render_token "$rendered" __PYTHON__ "$python_path"
    render_token "$rendered" __AGY_STATUSLINE__ "$agy_dir/statusline.py"
    merge_agent_settings "$rendered" "$agy_dir/settings.json"
    if [ ! -f "$agy_dir/mcp.json" ]; then
        cp "$REPO_CONFIG_DIR/antigravity/mcp.json" "$agy_dir/mcp.json"
    fi

    # Opencode: global config dir is ~/.config/opencode (same path on Windows:
    # %USERPROFILE%\.config\opencode). Opencode does not parse @file imports in
    # AGENTS.md; opencode.json lists the shared docs via its instructions array
    # (paths relative to the config file). opencode.json is seed-if-missing
    # ONLY — opencode writes user prefs (model, theme) into it at runtime.
    local oc_dir="$HOME/.config/opencode"
    mkdir -p "$oc_dir"
    cp -f "$REPO_CONFIG_DIR/opencode/AGENTS.md" "$oc_dir/AGENTS.md"
    deploy_shared_agent_docs "$oc_dir"
    if [ ! -f "$oc_dir/opencode.json" ]; then
        cp "$REPO_CONFIG_DIR/opencode/opencode.json" "$oc_dir/opencode.json"
    fi
}

install_secrets_scaffold() {
    # Machine-local secrets live OUTSIDE the repo, sourced by core.zsh.
    mkdir -p "$HOME/.secrets"
    chmod 700 "$HOME/.secrets"
    if [ ! -f "$HOME/.secrets/env.sh" ]; then
        cat > "$HOME/.secrets/env.sh" <<'EOF'
# Machine-local secrets — auto-sourced by every zsh shell. NEVER commit this file.
# Do NOT export ANTHROPIC_API_KEY here: a global key forces API billing even
# with a subscription login.
# export OPENAI_API_KEY="..."   # only if not using `codex login`
EOF
        chmod 600 "$HOME/.secrets/env.sh"
    fi
}

install_node_shims() {
    # Railguard for non-interactive consumers (Claude Code hooks, cron,
    # /bin/sh scripts): nvm only puts node on PATH in interactive shells, so
    # anything running under plain sh sees "node: not found". If node exists
    # ONLY via nvm, shim it into ~/.local/bin. core.zsh APPENDS ~/.local/bin
    # to PATH, so a real system node always wins — the shim is pure fallback.
    local sysbin nvm_dir ver target t
    mkdir -p "$HOME/.local/bin"

    # Repair pass: drop dangling shims (e.g. after `nvm uninstall`)
    for t in node npm npx; do
        if [ -L "$HOME/.local/bin/$t" ] && [ ! -e "$HOME/.local/bin/$t" ]; then
            rm -f "$HOME/.local/bin/$t"
        fi
    done

    # A system-wide node already serves non-interactive shells
    for sysbin in /usr/bin/node /usr/local/bin/node /opt/homebrew/bin/node; do
        if [ -x "$sysbin" ]; then
            echo "System node at $sysbin; no shim needed"
            return 0
        fi
    done

    nvm_dir="$HOME/.nvm/versions/node"
    if [ ! -d "$nvm_dir" ]; then
        echo "No system node and no nvm; nothing to shim"
        return 0
    fi

    # Prefer nvm's default alias when it names an installed version directly;
    # indirect aliases (lts/*) need nvm itself, so fall back to the newest.
    ver=""
    if [ -f "$HOME/.nvm/alias/default" ]; then
        ver="$(cat "$HOME/.nvm/alias/default")"
        [ -d "$nvm_dir/$ver" ] || ver=""
    fi
    if [ -z "$ver" ]; then
        ver="$(ls "$nvm_dir" 2>/dev/null | sort -V | tail -n 1)"
    fi
    if [ -z "$ver" ]; then
        echo "nvm present but no node versions installed; nothing to shim"
        return 0
    fi

    target="$nvm_dir/$ver/bin"
    for t in node npm npx; do
        if [ -x "$target/$t" ]; then
            ln -sf "$target/$t" "$HOME/.local/bin/$t"
        fi
    done
    echo "Shimmed node $ver into ~/.local/bin for non-interactive shells"
}

# 1. .config folders — driven by installation/config_manifest
# (name tier mode [sentinel]; see the manifest header for the schema). Not
# itself run_step-wrapped: each module prints its own status line, and a
# failing module aborts via set -e exactly like the old top-level run_steps.
deploy_config_modules() {
    local name tier mode sentinel
    while read -r name tier mode sentinel; do
        case "$name" in ''|'#'*) continue ;; esac
        if [ "$tier" = "internal" ]; then
            continue  # deployed by the dedicated steps below
        fi
        # Seed mode: once the sentinel file exists the module is
        # runtime-managed — copying over it would clobber tool-written state.
        # Herdr's shared seed leaves default_shell empty to use $SHELL on
        # Unix/WSL; forcing the Windows pwsh default breaks Linux panes.
        if [ "$mode" = "seed" ] && [ -e "$CONFIG_DIR/$name/${sentinel:-}" ]; then
            skip_step "Config: $name" "exists (runtime-managed)"
            continue
        fi
        run_step "Config: $name" copy_config "$name"
    done < "$REPO_ROOT/installation/config_manifest"
}
deploy_config_modules

# 2. Terminal Shell Files
run_step "Shell configs" install_shell_configs

# 3. Scripts
run_step "Local scripts" install_scripts

# 4. Tmux
run_step "Tmux config" install_tmux_config
run_step "Shell speedup (zcompile)" install_shell_speedup

# 5. Agent configs (Claude Code / Codex) + secrets scaffold
run_step "Agent configs" install_agent_configs
run_step "Secrets scaffold" install_secrets_scaffold

# 6. Node railguard for hooks/cron (nvm is interactive-only)
run_step "Node shims" install_node_shims

success "Configuration files ready."
