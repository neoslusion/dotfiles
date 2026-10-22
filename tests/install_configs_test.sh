#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TMP_DIR"' EXIT
# Registration must be tested without invoking an installed CLI or its services.
# The installer must not pin CLAUDE_CONFIG_DIR: the CLI would then look for its
# global config at ~/.claude/.claude.json and create a stray one.
unset CLAUDE_CONFIG_DIR
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/claude" <<'EOF'
#!/bin/sh
set -eu
[ -z "${CLAUDE_CONFIG_DIR:-}" ]
printf '%s\n' "$*" >> "$HOME/.claude/mod-registration.log"
EOF
chmod +x "$TMP_DIR/bin/claude"
export PATH="$TMP_DIR/bin:/usr/bin:/bin:$PATH"
# Git Bash: the claude CLI's home is USERPROFILE, and the installer only
# registers mods when it matches HOME.
if command -v cygpath >/dev/null 2>&1; then
    USERPROFILE="$(cygpath -w "$TMP_DIR/home")"
    export USERPROFILE
fi

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf "Expected output to contain: %s\n\nOutput was:\n%s\n" "$needle" "$haystack" >&2
        return 1
    fi
}

mkdir -p "$TMP_DIR/home/.local/bin"
legacy_launcher="rice"
printf "old launcher\n" > "$TMP_DIR/home/.local/bin/$legacy_launcher"
printf "old sessionizer\n" > "$TMP_DIR/home/.local/bin/sessionizer"

# Pre-existing Codex config.toml must survive a refresh (runtime-managed)
mkdir -p "$TMP_DIR/home/.codex"
printf '# user-accumulated trust entries\n' > "$TMP_DIR/home/.codex/config.toml"

# Claude settings.json and CLAUDE.md are shared with other installers (e.g.
# rtk): their entries must survive both installs.
mkdir -p "$TMP_DIR/home/.claude"
cp "$ROOT/tests/fixtures/claude_settings_live.json" "$TMP_DIR/home/.claude/settings.json"
printf '@RTK.md\n' > "$TMP_DIR/home/.claude/CLAUDE.md"
printf '@RTK.md\n' > "$TMP_DIR/home/.codex/AGENTS.md"
# Antigravity writes its own keys into settings.json; an existing install
# may still carry a stale statusline command.
mkdir -p "$TMP_DIR/home/.gemini/antigravity-cli"
printf '{"model": "kept", "statusLine": {"type": "command", "command": "python old.py", "enabled": true}}\n' \
    > "$TMP_DIR/home/.gemini/antigravity-cli/settings.json"

# User-managed instructions, commands, and skills must survive both installs.
printf 'user-managed content\n' > "$TMP_DIR/unmanaged.md"
agent_homes=(.claude .codex .gemini/antigravity-cli .config/opencode)
unmanaged_files=(CUSTOM.md commands/custom.md skills/custom/SKILL.md)
for agent_home in "${agent_homes[@]}"; do
    for file in "${unmanaged_files[@]}"; do
        target="$TMP_DIR/home/$agent_home/$file"
        mkdir -p "$(dirname "$target")"
        cp "$TMP_DIR/unmanaged.md" "$target"
    done
done

HOME="$TMP_DIR/home" \
XDG_STATE_HOME="$TMP_DIR/state" \
DOTFILES_LOG_FILE="$TMP_DIR/install.log" \
    bash "$ROOT/installation/install_configs.sh" >/dev/null

# Agent configs: seeds deployed, config.toml untouched, no key material
if [[ ! -f "$TMP_DIR/home/.claude/settings.json" || ! -f "$TMP_DIR/home/.claude/CLAUDE.md" ]]; then
    printf "Expected Claude agent configs to be deployed.\n" >&2
    exit 1
fi

if ! diff -r "$ROOT/config/claude/mods" "$TMP_DIR/home/.claude/mods" >/dev/null; then
    printf "Expected Claude mods to be deployed verbatim to ~/.claude/mods.\n" >&2
    exit 1
fi

if [[ ! -f "$TMP_DIR/home/.codex/AGENTS.md" ]]; then
    printf "Expected Codex agent configs to be deployed.\n" >&2
    exit 1
fi

# Statusline commands must be fully rendered, or the agent runs a literal token.
if grep -q '__[A-Z_]*__' "$TMP_DIR/home/.claude/settings.json" \
    "$TMP_DIR/home/.gemini/antigravity-cli/settings.json"; then
    printf "Statusline tokens left unrendered in agent settings.\n" >&2
    exit 1
fi

if [[ ! -f "$TMP_DIR/home/.gemini/antigravity-cli/AGENTS.md" ]]; then
    printf "Expected Antigravity agent configs to be deployed.\n" >&2
    exit 1
fi
if ! python3 - "$TMP_DIR/home/.gemini/antigravity-cli/settings.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
assert s["model"] == "kept", "foreign key dropped"
assert s["statusLine"]["command"].endswith('/.gemini/antigravity-cli/statusline.py') and '"' not in s["statusLine"]["command"], "stale statusLine kept"
EOF
then
    printf 'Expected Antigravity settings.json to keep its keys and get the current statusLine.\n' >&2
    exit 1
fi

# Opencode: AGENTS.md + shared docs deployed; opencode.json seeded and must
# list the shared docs in its instructions array (opencode has no @file imports).
if [[ ! -f "$TMP_DIR/home/.config/opencode/AGENTS.md" \
    || ! -f "$TMP_DIR/home/.config/opencode/opencode.json" ]]; then
    printf "Expected Opencode agent configs to be deployed.\n" >&2
    exit 1
fi
if ! grep -qF '"ENGINEERING.md"' "$TMP_DIR/home/.config/opencode/opencode.json"; then
    printf "Expected opencode.json instructions to include ENGINEERING.md.\n" >&2
    exit 1
fi

# Shared engineering guidance lands in every agent home.
for home in "$TMP_DIR/home/.claude" "$TMP_DIR/home/.codex" \
            "$TMP_DIR/home/.gemini/antigravity-cli" "$TMP_DIR/home/.config/opencode"; do
    if [[ ! -f "$home/ENGINEERING.md" ]]; then
        printf "Expected ENGINEERING.md deployed to %s.\n" "$home" >&2
        exit 1
    fi
done

if [[ ! -d "$TMP_DIR/home/.config/herdr" || ! -f "$TMP_DIR/home/.config/herdr/config.toml" ]]; then
    printf "Expected Herdr seed config to be deployed.\n" >&2
    exit 1
fi

# The shared seed must allow Herdr to select the host shell on Unix/WSL.
if grep -qE '^[[:space:]]*default_shell[[:space:]]*=[[:space:]]*"[^"]+' "$TMP_DIR/home/.config/herdr/config.toml"; then
    printf 'Herdr seed must let the runtime select the host shell.\n' >&2
    exit 1
fi

# Herdr config is runtime-managed after seeding (Settings TUI writes back):
# a second run must NOT overwrite it.
printf '\n[ui]\ntab_bar_position = "bottom"\n' >> "$TMP_DIR/home/.config/herdr/config.toml"
# Copy-managed configs are only backed up when their content changed.
printf '# local edit\n' >> "$TMP_DIR/home/.config/lazygit/config.yml"
# Claude rewrites settings.json in its own JSON style; a refresh that changes no
# content must leave the file as it is (no rewrite, no fresh .bak).
python3 -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p)); open(p, "w").write(json.dumps(d, separators=(",", ":")))' \
    "$TMP_DIR/home/.claude/settings.json"
cp "$TMP_DIR/home/.claude/settings.json" "$TMP_DIR/settings.restyled"
HOME="$TMP_DIR/home" \
XDG_STATE_HOME="$TMP_DIR/state" \
DOTFILES_LOG_FILE="$TMP_DIR/install.log" \
    bash "$ROOT/installation/install_configs.sh" >/dev/null
if ! grep -q 'tab_bar_position' "$TMP_DIR/home/.config/herdr/config.toml"; then
    printf "Expected Herdr config.toml to be left untouched after seeding.\n" >&2
    exit 1
fi
if ! grep -q '# local edit' "$TMP_DIR/home/.config/lazygit.bak/config.yml" 2>/dev/null \
    || ! diff -r "$ROOT/config/lazygit" "$TMP_DIR/home/.config/lazygit" >/dev/null; then
    printf 'Expected a changed config to be restored, with the edit kept as .bak.\n' >&2
    exit 1
fi
for unchanged in .config/nvim .claude/mods; do
    if [[ -e "$TMP_DIR/home/$unchanged.bak" ]]; then
        printf 'Expected no backup of the unchanged %s.\n' "$unchanged" >&2
        exit 1
    fi
done
if ! cmp -s "$TMP_DIR/settings.restyled" "$TMP_DIR/home/.claude/settings.json"; then
    printf 'Expected an unchanged Claude settings.json to be left as is.\n' >&2
    exit 1
fi

if ! python3 - "$TMP_DIR/home/.claude/settings.json" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
assert s["cleanupPeriodDays"] == 3650, "foreign key dropped"
assert s["hooks"]["PreToolUse"][0]["hooks"][0]["command"] == "rtk hook claude", "rtk hook dropped"
assert s["hooks"]["SessionStart"][0]["matcher"] == "startup", "foreign hook dropped"
assert s["enabledPlugins"]["caveman@caveman"] is True, "user plugin dropped"
assert s["env"]["USER_VAR"] == "kept", "nested user key dropped"
assert s["env"]["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] == "1", "nested repo key not merged"
assert s["theme"] == "dark", "repo key did not win"
assert "statusline.py" in s["statusLine"]["command"], "statusLine not merged"
EOF
then
    printf 'Expected Claude settings.json merge to keep foreign keys and apply repo keys.\n' >&2
    exit 1
fi
if [[ ! -f "$TMP_DIR/home/.claude/settings.json.bak" ]]; then
    printf 'Expected the pre-merge Claude settings.json to be kept as .bak.\n' >&2
    exit 1
fi
for pair in ".claude/CLAUDE.md|@ENGINEERING.md" ".codex/AGENTS.md|@~/.codex/ENGINEERING.md"; do
    file="$TMP_DIR/home/${pair%%|*}"
    import="${pair#*|}"
    if ! grep -qxF '@RTK.md' "$file" || [[ "$(grep -cxF "$import" "$file")" -ne 1 ]]; then
        printf 'Expected %s to keep @RTK.md and import %s exactly once.\n' "${pair%%|*}" "$import" >&2
        exit 1
    fi
done

registration_log="$TMP_DIR/home/.claude/mod-registration.log"
if [[ "$(grep -Fxc "plugin marketplace add $TMP_DIR/home/.claude/mods" "$registration_log")" -ne 2 ]]; then
    printf 'Expected Claude marketplace registration on both installs.\n' >&2
    exit 1
fi
mod_names="$(python3 -c 'import json, sys; print("\n".join(p["name"] for p in json.load(open(sys.argv[1]))["plugins"]))' "$ROOT/config/claude/mods/.claude-plugin/marketplace.json" | tr -d '\r')"
while IFS= read -r mod; do
    if [[ "$(grep -Fxc "plugin install $mod@my-mods --scope user" "$registration_log")" -ne 2 ]]; then
        printf 'Expected Claude mod installation on both installs: %s\n' "$mod" >&2
        exit 1
    fi
done <<< "$mod_names"
# With HOME redirected away from the CLI's real home, registering would point
# the real registry at a temp dir that is later deleted.
if command -v cygpath >/dev/null 2>&1; then
    registrations="$(wc -l < "$registration_log")"
    HOME="$TMP_DIR/home" \
    USERPROFILE="$(cygpath -w "$TMP_DIR")" \
    XDG_STATE_HOME="$TMP_DIR/state" \
    DOTFILES_LOG_FILE="$TMP_DIR/install.log" \
        bash "$ROOT/installation/install_configs.sh" >/dev/null
    if [[ "$(wc -l < "$registration_log")" -ne "$registrations" ]]; then
        printf 'Expected no mod registration when the claude CLI home is not HOME.\n' >&2
        exit 1
    fi
fi

for agent_home in "${agent_homes[@]}"; do
    for file in "${unmanaged_files[@]}"; do
        if ! cmp -s "$TMP_DIR/unmanaged.md" "$TMP_DIR/home/$agent_home/$file"; then
            printf 'Expected user-managed content to survive refresh: %s/%s\n' "$agent_home" "$file" >&2
            exit 1
        fi
    done
done

if ! grep -q "user-accumulated trust entries" "$TMP_DIR/home/.codex/config.toml"; then
    printf "Expected pre-existing Codex config.toml to be left untouched.\n" >&2
    exit 1
fi

if grep -qE "ANTHROPIC_API_KEY\"?\s*[:=]\s*[\"'][^\"']+|apiKeyHelper" "$TMP_DIR/home/.claude/settings.json"; then
    printf "Deployed Claude settings.json must not carry key material.\n" >&2
    exit 1
fi

if [[ ! -f "$TMP_DIR/home/.secrets/env.sh" ]]; then
    printf "Expected secrets scaffold at ~/.secrets/env.sh.\n" >&2
    exit 1
fi

if [[ -e "$TMP_DIR/home/.local/bin/$legacy_launcher" ]]; then
    printf "Expected stale launcher binary to be removed.\n" >&2
    exit 1
fi

if [[ -e "$TMP_DIR/home/.local/bin/sessionizer" ]]; then
    printf "Expected stale sessionizer binary to be removed.\n" >&2
    exit 1
fi

if [[ ! -f "$TMP_DIR/home/.local/bin/audit_nvim_keymaps.py" ]]; then
    printf "Expected audit_nvim_keymaps.py to be installed next to audit-nvim-keymaps.\n" >&2
    exit 1
fi

cat > "$TMP_DIR/home/.config/nvim/lua/config/codex_duplicate_test.lua" <<'EOF'
vim.keymap.set("n", "<leader>zz", function() end)
vim.keymap.set("n", "<leader>zz", function() end)
EOF

# Native Windows (Git Bash): python3 is the Python install manager's alias.
# Without LOCALAPPDATA it installs a whole runtime into the current directory,
# and Python finds the home directory through USERPROFILE, not HOME.
win_env=()
if [[ -n "${LOCALAPPDATA:-}" ]]; then
    win_env=(LOCALAPPDATA="$LOCALAPPDATA" USERPROFILE="$TMP_DIR/home")
fi

set +e
output="$(
    env -i \
        HOME="$TMP_DIR/home" \
        ${win_env[@]+"${win_env[@]}"} \
        XDG_CONFIG_HOME="$TMP_DIR/home/.config" \
        PATH="$TMP_DIR/home/.local/bin:/usr/bin:/bin:$PATH" \
        audit-nvim-keymaps 2>&1
)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
    printf "Expected installed audit-nvim-keymaps to find duplicate keymaps.\n\nOutput was:\n%s\n" "$output" >&2
    exit 1
fi

assert_contains "$output" "Duplicate Neovim keymaps"
assert_contains "$output" "<leader>zz"

# Perf: managed ~/.zshenv must be deployed (kills Ubuntu's duplicate compinit)
if ! grep -q "skip_global_compinit=1" "$TMP_DIR/home/.zshenv" 2>/dev/null; then
    printf "Expected ~/.zshenv with skip_global_compinit=1 to be deployed.\n" >&2
    exit 1
fi

printf "install config tests passed\n"
