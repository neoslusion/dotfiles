# Repository Guidelines

## Project Overview

Dotfiles for Debian/Ubuntu (incl. WSL), Arch, Fedora, macOS and native Windows,
managed by chezmoi. `.chezmoiroot` makes `home/` the source state; everything
outside `home/` is repo tooling and never deployed. No build step, no installer
of our own: `chezmoi init --apply` is the only entry point. Everything installs
at its latest version; the one pin is Windows Python (`versions/python314`),
because the global venv is built on it.

## Layout

- `home/`: files deployed to `$HOME`, in chezmoi naming. `dot_x` -> `.x`,
  `executable_` sets +x, `private_` sets 0600/0700, `create_` writes only when
  missing, `modify_` transforms the live file, `.tmpl` renders as a template.
  Dot-named entries other than `.chezmoi*` are ignored by chezmoi, so a
  directory such as `.claude-plugin` must be named `dot_claude-plugin`.
- `home/.chezmoi.toml.tmpl`: generated config (`sourceDir` = the checkout; `.ps1` scripts run under pwsh).
- `home/.chezmoiignore`: per-OS exclusions (Windows-only `AppData/`, `PowerShell/`; Unix-only zsh/tmux/mise/`.local`; sketchybar on macOS only).
- `home/.chezmoidata/packages.yaml`: base packages per manager (apt, pacman, dnf, brew, scoop).
- `home/.chezmoiscripts/`: `run_onchange_after_10-install-packages` (.sh + .ps1; Unix also installs mise and runs `mise install`), `20-windows-setup.ps1` (`XDG_CONFIG_HOME`, `$PROFILE` line), `30-register-claude-mods` (.sh + .ps1). Each script is a template wrapped in an OS guard, so it renders empty, and is skipped, elsewhere. `.ps1.tmpl` scripts have no BOM for the same reason.
- `home/.chezmoiexternal.toml.tmpl`: Oh My Zsh + plugins, TPM, Linux Nerd Font.
- `home/.chezmoitemplates/`: shared sources: `ENGINEERING.md`, `claude-settings.json`, `antigravity-settings.json`, and helpers `python-path`, `merge-json`, `ensure-line`, `mods-hash`.
- `home/dot_config/mise/config.toml`: every Unix CLI tool and runtime.
- `home/dot_config/nvim/`: Neovim (`init.lua`, `lua/config/`, `lua/plugins/`, `after/lsp/`).
- `home/dot_claude/mods/`: first-party Claude Code mods (`my-mods` folder marketplace).
- `.github/workflows/ci.yml`: gitleaks, shellcheck, full `chezmoi init --apply` on ubuntu/macos/arch/fedora, files-only apply on Windows.

## Development Commands

```bash
chezmoi diff                    # read-only: what apply would change on this machine
chezmoi apply [target]          # deploy (all, or one path such as ~/.config/nvim)
chezmoi apply --exclude scripts # files only
chezmoi re-add                  # copy live edits of plain managed files back into home/
chezmoi execute-template < home/<file>.tmpl   # render one template
chezmoi managed                 # what chezmoi manages on this OS
pre-commit install              # gitleaks on commit
```

## Conventions

- **Windows paths.** Neovim, lazygit and herdr read `~/.config` on Windows only
  because `20-windows-setup` sets `XDG_CONFIG_HOME`; keep their configs under
  `dot_config/`, never duplicated under `AppData/`. Alacritty ignores XDG on
  Windows, so it lives under `home/AppData/Roaming/`.
- **Shared, tool-written files are merged, never replaced.** `~/.claude/settings.json`
  and Antigravity's `settings.json` use `modify_` + `merge-json` (repo keys win,
  nested objects merge, other keys kept, unchanged content returns the live
  text). `CLAUDE.md`, Codex `AGENTS.md` and `.zprofile` use `ensure-line`
  because rtk and other installers append to them. In modify-templates and in
  templates they include, call shared templates with `includeTemplate`, not
  `template` (chezmoi does not define them there).
- **Runtime-owned files are `create_`:** herdr, Codex `config.toml`, opencode
  `opencode.json`, Antigravity `mcp.json`, `.wslconfig`, secrets scaffolds.
- **Machine paths come from templates:** `{{ .chezmoi.homeDir }}`,
  `includeTemplate "python-path"` (absolute interpreter for the statuslines;
  never the WindowsApps alias). Forward slashes inside JSON.
- **A script re-runs when its rendered text changes:** embed a hash of any input
  it depends on (`{{ include "..." | sha256sum }}`, `mods-hash`).
- **Packages:** add to `packages.yaml` (Unix base packages, Scoop on Windows) or
  to `mise/config.toml` (Unix CLI tools). Do not add pins beyond the
  Windows Python one; `python-path` finds whichever `python3*` Scoop app is installed.
- **PowerShell:** pwsh 7 only, ASCII-only literals, `$ErrorActionPreference = 'Stop'`
  first. Plain `*.ps1` files are UTF-8 with BOM + CRLF (`.gitattributes`);
  `*.ps1.tmpl` scripts are LF without a BOM.
- **Comments are load-bearing:** keep platform gotchas and "don't do the obvious
  thing because X". Trim restatements only.
- `~/.claude/rules/` (vault.md, orchestrator.md) belongs to other repos; never manage it here.

## Agents

- `ENGINEERING.md` is the only shared agent content, deployed to `~/.claude`,
  `~/.codex`, `~/.gemini/antigravity-cli`, `~/.config/opencode`.
- The only plugins installed are this repo's Claude Code mods. No other
  plugins, marketplaces or hook tools.
- Secrets: scaffolds only (`~/.secrets/env.sh`, `env.ps1`), never repo content.

## Testing & QA

- Before handing back: `chezmoi diff` on this machine must show only intended
  changes, and must render without errors (it renders every template and
  modify-template against the live files, read-only).
- CI is the end-to-end test: fresh `chezmoi init --apply` per platform, then
  `chezmoi verify` and tool checks. Unix scripts can only really be tested
  there or in a container.
- Neovim keymaps: `python3 home/dot_local/bin/audit_nvim_keymaps.py home/dot_config/nvim`.
