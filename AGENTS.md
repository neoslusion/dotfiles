# Repository Guidelines

## Project Overview

Dotfiles + installer for Debian/Ubuntu (incl. WSL), Arch, Fedora, macOS, plus standalone native-Windows subsystem in `windows/` (not wired into `install.sh`).
Installs packages and copies configs into place. No build step; `set -e` scripts, exit 0 = success.

## Architecture & Data Flow

Linux/WSL/macOS path:

```text
install.sh -> installation/common_install.sh -> installation/preflight_config.sh -> installation/install_configs.sh -> TPM
                |-> install_core/shell/agents/cli_tools/bars.sh        |-> doctor.sh on --doctor (non-mutating branch)
                +-- installation/utils.sh (sourced everywhere, auto-sources versions.env)
```

- `install.sh`: only user entry. Full run = 4 phases (deps + preflight + configs + TPM clone). `--config` skips deps, runs preflight + configs only. `--doctor` execs `installation/doctor.sh` and exits.
- `installation/common_install.sh`: runs `prepare_system_packages` once, then Core/Shell/Agents/CLI/Bars sections.
- `installation/preflight_config.sh`: `bash -n` sweep, `audit-nvim-keymaps`, `tmux source-file -n`, `python json.tool` gates before any deploy.
- `installation/install_configs.sh`: manifest-driven `copy_config` + dedicated `internal` steps (shell, tmux, agents, secrets, shims).
- Windows path mirrors it: `install.ps1` -> `windows/install.ps1` (+ `windows/dotsync.ps1`, `windows/doctor.ps1`). Same `config/` source of truth, same `__TOKEN__` rendering. Any deploy change (esp. `config/claude/`) must land in both installers in same commit.

## Key Directories

- `installation/`: internal installer blocks. `utils.sh` toolbox, `versions.env` pins, `release_assets` per-arch asset table, `config_manifest` deploy list, `install_*.sh` per-domain installers, `doctor.sh`, `preflight_config.sh`.
- `config/`: source of truth, 15 tool dirs. `config/<tool>/` per tool; deployed by copy, never symlink.
- `scripts/`: runtime helpers (`bump-version`, `sync-nvim-locks`, `bootstrap`, `dotsync`, `sys-info`, `audit-nvim-keymaps`, `utils/paths.sh`).
- `windows/`: native-Windows subsystem (Alacritty + pwsh 7, `install.ps1`, `$WingetPins`, `profile.ps1`, `doctor.ps1`, `dotsync.ps1`).
- `tests/`: bash suites + `*.ps1` suites + `run_all.sh` orchestrator + `distro_smoke.sh` container test.
- `.github/workflows/`: `ci.yml` gates, `drift.yml` weekly pin-drift reporter. `.githooks/pre-commit` opt-in fast gate.

## Development Commands

```bash
./install.sh                 # full core install
./install.sh --config        # reapply configs only (also --config-only)
./install.sh --doctor        # non-mutating health check
./install.sh --verbose       # stream step logs (default quiet to $DOTFILES_LOG_FILE)

scripts/dotsync nvim         # fast redeploy one module; `all|--list|--dry-run`
scripts/bump-version lazygit # bump one pin; --dry-run previews; --check reports all drift
scripts/sync-nvim-locks      # snapshot lazy/mason locks into config/nvim/; --restore reverses
bash tests/run_all.sh        # all local suites; --smoke adds docker smoke
bash tests/<name>_test.sh    # single suite, e.g. bash tests/install_policy_test.sh
bash tests/distro_smoke.sh [ubuntu:22.04|fedora:latest|archlinux:latest]
git config core.hooksPath .githooks  # enable pre-commit
```

Windows (pwsh 7, non-elevated):

```powershell
.\install.ps1                # forwards to windows/install.ps1
.\install.ps1 -ConfigOnly    # skip tools; also -NoAdmin -Winget
pwsh -File windows\doctor.ps1
```

## Code Conventions & Common Patterns

Architecture patterns to follow, not reinvent:

- **Bash header:** `#!/bin/bash` + `set -e` minimum (helpers use `set -euo pipefail`). `echo "Message..."` for progress. Absolute paths or `$HOME`.
- **Idempotency guard (primary idiom):** `check_and_install <cmd> <label> <fn>` (`command -v` guard) and `check_dir_and_run <dir> <label> <fn>` (`[ -d ]` guard). Example: `check_and_install nvim "Neovim" install_nvim`.
- **Step wrapper:** `run_step "<label>" <cmd...>` (quiet to log, prints `ok/fail`); `skip_step "<label>" "<reason>"`. Preserve `set -e`: `|| status=$?` pattern in `utils.sh`.
- **Packages — never call `apt`/`dnf`/`pacman` directly:** `system_install <debian-names>` from `installation/utils.sh`. Always pass Debian names; add `map_package` entry when Arch/Fedora differ (empty = skip with warning). Example: `system_install zsh git curl fd-find` (`fd-find` -> `fd` elsewhere). `sudo` explicit; `sudo DEBIAN_FRONTEND=noninteractive apt-get ...` (env must ride sudo).
- **Network binaries:** `install_release_binary <url> <find-pattern> <dest> <sha256>` (tarball-only; musl where available) with `DOTFILES_<TOOL>_VERSION` + per-arch `_SHA256` in `installation/versions.env`. Resolve asset name + SHA via `release_asset <tool> asset sha256` (one row per tool in `installation/release_assets`, shared with `bump-version`); never hand-roll `uname -m` cases. Bare binaries use bespoke fns (herdr). TPM uses the exact `DOTFILES_TPM_REF` commit. Never install unpinned tarballs.
- **Pin style matters:** `tag` keeps `v` prefix (`nvim`, `herdr` interpolate raw into `releases/download/<tag>/`); else `bare` strips it. Enforced by `tests/bump_version_test.sh`.
- **Config deployment — copy, don't symlink:** `cp -R src/. dest/` with `<dest>.bak` backup; a dest whose content already matches is left alone (no rewrite, no fresh `.bak`). Manifest line in `installation/config_manifest`: `name tier mode [sentinel]` — tier `core|internal`, mode `copy|seed|-`. Every `config/` dir must have one manifest line (`tests/install_policy_test.sh` fails otherwise). `copy` refreshes every run; `seed` creates-only-if-missing (sentinel-gated, e.g. `herdr ... seed config.toml`; codex/antigravity/opencode use inline `if [ ! -f ... ]` guards). `internal` = deployed by dedicated fns, skipped by manifest loop. `~/.claude/settings.json` is shared with other installers (e.g. rtk), so it is merged, never replaced: `installation/merge_settings.py` (bash) and `Merge-JsonObject` (`windows/install.ps1`, must stay WinPS 5.1-safe) apply identical rules, pinned by the shared `tests/fixtures/claude_settings_live.json`. `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` only get their ENGINEERING.md import line ensured (`inject_sourcing` / `Add-ImportLine`), since rtk adds its own line.
- **Machine paths via tokens:** never hardcode; use `__TOKEN__` rendered at deploy time by both installers. `__PYTHON__` (absolute interpreter: `command -v python3`; on Windows the real `python.exe`, never the WindowsApps alias), `__CLAUDE_STATUSLINE__`, `__AGY_STATUSLINE__`. Tests assert no token survives.
- **Sudo/index guards:** `prepare_system_packages` runs `apt-get update` / `pacman -Syu` once per run (`DOTFILES_APT_INDEX_REFRESHED` / `DOTFILES_PACMAN_SYNCED`).
- **PowerShell:** UTF-8 with BOM + CRLF + ASCII-only string literals (WinPS 5.1 rule; glyphs via `[char]`). Every `*.ps1` starts `$ErrorActionPreference='Stop'`. `.gitattributes` enforces LF for `*.sh`, CRLF for `*.ps1`.
- **Comments are load-bearing:** keep platform gotchas, pin reasoning, "don't do the obvious thing because X". Trim restatements only.

## Important Files

- Entry: `install.sh`, `install.ps1` -> `windows/install.ps1`, `installation/common_install.sh`, `installation/utils.sh`, `installation/install_configs.sh`, `installation/doctor.sh`, `installation/preflight_config.sh`.
- Pins/deploy: `installation/versions.env`, `installation/release_assets`, `installation/config_manifest`, `windows/install.ps1` (`$WingetPins` parity with `versions.env`).
- Shell/nvim/tmux: `config/nvim/init.lua` (+ `lua/config/settings.lua`, `keymaps.lua`, `lua/plugins/`), `config/terminal/.zshrc|.zshenv|core.zsh|starship.toml`, `config/tmux/.tmux.conf|tmux.core.conf`, `config/atuin/config.toml`, `config/lazygit/config.yml`.
- Agents: `config/agents/ENGINEERING.md` copied verbatim into `~/.claude`, `~/.codex`, `~/.gemini`, `~/.config/opencode`; `config/claude/settings.json`, `config/codex/config.toml`, `config/opencode/opencode.json`, `config/antigravity/settings.json`. The only plugins installed are the repo's own Claude Code mods (`config/claude/mods/` -> `~/.claude/mods/`, registered as the `my-mods` folder marketplace via the `claude` CLI each refresh); no other plugins/marketplaces/hook tools. ENGINEERING.md is the only shared agent content.
- Secrets (scaffold only, never repo content): `~/.secrets/env.sh` (600/700).

## Runtime/Tooling Preferences

- Bash on Linux/macOS/WSL; pwsh 7 only on Windows (never WinPS 5.1, run non-elevated).
- Package managers: `system_install` abstraction on Linux; `brew` branch on macOS; Scoop-first with winget fallback on Windows (`Install-App`; `-Winget` inverts, `-NoAdmin` forces Scoop-only).
- Node via nvm lazy-load (`config/terminal/core.zsh`) + `~/.local/bin` shims; Mason needs `npm` on PATH. Windows Copilot needs system Node via winget. `python3` for `audit_nvim_keymaps.py` and both agent statuslines (`config/claude/statusline.py`, `config/antigravity/statusline.py`).
- Tooling gates: `shellcheck -S warning` on all `*.sh`/`*.bash` + 4 extensionless scripts; `bash -n` in pre-commit; `gitleaks` full-history in CI, `protect --staged` in hook.

## Testing & QA

No test framework; pure bash asserts + pwsh dry-runs, mktemp `HOME`, `trap rm -rf`.

- `tests/run_all.sh`: 10 bash suites fixed order (`install_policy`, `bootstrap`, `path_policy`, `doctor`, `install_agents`, `install_utils`, `install_configs`, `shell_config`, `config_preflight`, `bump_version`); `--smoke` adds `distro_smoke`; runs `windows_preflight` + `windows_profile` iff `pwsh` is on PATH, and `windows_dryrun` only on native Windows (it runs the real installer).
- Key suites: `install_policy_test.sh` (SHA format, no floating `curl|sh`/`git clone`, SHA-pinned Actions, manifest parity, Windows deploy parity via `windows_skip` allowlist), `doctor_test.sh` (copy-managed config drift detection), `install_agents_test.sh` (vendor-installer opt-out), `install_utils_test.sh` (lazy log file, every `release_assets` row resolves to a real pin), `install_configs_test.sh` (full deploy into mktemp HOME: seeds, unrelated agent content preservation, herdr/codex preservation, stale-bin cleanup), `config_preflight_test.sh` (duplicate `<leader>` keymap fixture must fail), `bump_version_test.sh` (offline via `DOTFILES_BUMP_TEST_*` seams, never network), `distro_smoke.sh` (manual docker full `./install.sh` on ubuntu/fedora/arch; exit 0 if no docker; never pipe through `grep|tail`).
- CI (`ci.yml`, actions pinned by commit SHA): `bash-tests` (shellcheck + `run_all.sh`), `macos` (`run_all.sh` under stock `/bin/bash` 3.2, so no bash 4+ features or GNU-only `sed -i`), `secrets-scan` (gitleaks full history), `distro-smoke` (only on `installation/**`/`install.sh` change or dispatch), `windows` (always: preflight + dry-run). `drift.yml` runs `bump-version --check` weekly and only reports stale pins via issue.
- Expectations: suites must be deterministic, isolated, full-suite-safe; keep regression tests only for real contract/boundary/invariant breaks. Failing bar (wording/implementation pins) -> delete, never re-pin. Run `distro_smoke.sh` after any `installation/` change.
