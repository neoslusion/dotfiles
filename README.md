# Tokyo Night Dotfiles

A calm WSL/Linux terminal workspace: Zsh, tmux `Main`, Neovim, and a Tokyo Night theme. The normal path is intentionally boring; visual extras are optional.

Supported platforms: **Debian/Ubuntu (including WSL), Arch, Fedora, and macOS**. A standalone native-Windows setup lives in [`windows/`](windows/README.md).

## Install

```bash
git clone https://github.com/neoslusion/dotfiles.git ~/sandboxes/dotfiles
cd ~/sandboxes/dotfiles
./install.sh
```

Fresh machine, pinned checkout (the bootstrap script is fetched from the
default branch, but the checkout revision is fixed by the SHA argument):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/neoslusion/dotfiles/main/scripts/bootstrap) <commit-sha>
```

Pass `DOTFILES_ALLOW_MOVING_BOOTSTRAP_REF=1` only when intentionally tracking
a branch or tag. Override the checkout location with `DOTFILES_DEST`.

```bash
./install.sh --config     # reapply core configs only
./install.sh --verbose    # stream raw install output
./install.sh --doctor     # non-mutating health check
```


### Linux distros

`system_install` (in `installation/utils.sh`) detects the package manager
(`apt-get` → `dnf` → `pacman`, covering derivatives) and translates
Debian-canonical package names per distro via `map_package`. Tools missing
from a distro's repos come from SHA256-pinned GitHub release binaries
(musl builds), so behavior matches across distros. Validate installer changes against clean containers with:

```bash
bash tests/distro_smoke.sh                 # ubuntu:22.04 + fedora + arch
bash tests/distro_smoke.sh archlinux:latest  # one image
```

Installer logs live in:

```bash
~/.local/state/dotfiles/install-*.log
```

Network-installed tool versions are pinned in:

```bash
installation/versions.env
```

The release asset each tool downloads per architecture is listed once in
`installation/release_assets`, which both the installer and `bump-version` read.

Bump that file intentionally when you want newer upstream releases. For one-off testing, export an override such as `DOTFILES_NEOVIM_VERSION=v0.12.3` before running `./install.sh`.

Maintenance helpers:

```bash
scripts/bump-version lazygit          # bump a versions.env pin to latest (downloads + hashes)
scripts/bump-version nvim 0.12.4      # or pin an exact version (no v prefix); --dry-run to preview
scripts/bump-version --check          # report drift for every tool (read-only)
scripts/sync-nvim-locks               # snapshot live nvim plugin/LSP locks into the repo
git config core.hooksPath .githooks   # enable pre-commit checks (policy + gitleaks)
```

Bump tools one at a time so breakage stays bisectable. A weekly `drift`
workflow runs `--check` and reports stale pins as a GitHub issue (no code
changes).

## Health & Tests

Check the live setup (installed versions vs `versions.env` pins, config
deployment presence and parity, agent homes, secrets scaffold) without
changing anything:

```bash
./install.sh --doctor
```

For `copy`-managed config modules, doctor also checks that repository-owned
files still match the deployed files. User-created destination files and
runtime-managed `seed` files are intentionally ignored.
Run the full local test suite (Windows-side checks included when `pwsh` is
on PATH):

```bash
bash tests/run_all.sh                 # + --smoke to add the docker distro smoke
```

Git hooks are optional but recommended (fast policy/path checks on commit):

```bash
git config core.hooksPath .githooks
```

## MacOS Configuration

To ensure the best experience on MacOS (Terminal.app or iTerm2), you need to adjust a few terminal-level settings so that keys like `Alt` (Option) and `Home/End` work correctly.

### 1. Enable Option as Meta (Alt Key)
Most of the keybindings in this setup (pane switching, workspace management) use the `Alt` key. On Mac, you must tell your terminal to treat the `Option` key as `Meta`:
- **iTerm2:** Settings -> Profiles -> Keys -> General -> Set **Left Option Key** to `Esc+`.
- **Terminal.app:** Settings -> Profiles -> Keyboard -> Check **Use Option as Meta key**.

### 2. Home/End Keys
If your Home/End keys scroll the window instead of moving the cursor:
- **iTerm2:** Settings -> Profiles -> Keys -> Key Bindings -> Click **Presets...** -> Select **Natural Text Editing**.

## First Session

After install, close the current terminal and open a new one.

Expected default: a plain Zsh prompt. On Windows, herdr owns panes/tabs
(hjkl chords - see `windows/README.md`); tmux is installed but does not
auto-attach.

To restore the old auto-attached `Main` session:

```bash
DOTFILES_TMUX=1 zsh   # or export it in ~/.secrets/env.sh to make it stick
```

## Everyday

The daily command surface uses unified **Alt** chords across both **Herdr** (primary terminal workspace manager) and **Tmux** (terminal muxer), with seamless vim-aware navigation into **Neovim** splits and instant **Lazygit** popups:

| Key | Action | Herdr | Tmux | Neovim |
| :--- | :--- | :--- | :--- | :--- |
| `Alt + h / j / k / l` | Focus pane Left / Down / Up / Right | Focus pane | Focus / Neovim split | Move to split |
| `Alt + Arrow` | Move between Neovim splits | — (reaches the app) | — (reaches the app) | Move to split |
| `Alt + n` | Split side-by-side (vertical split) | Yes | Yes | — |
| `Alt + -` | Split stacked (horizontal split) | Yes | Yes | — |
| `Alt + z` | Toggle pane zoom / fullscreen | Yes | Yes | — |
| `Alt + q` | Close focused pane | Yes | Yes | `:q<CR>` |
| `Alt + t` | New tab / window | Yes | Yes | `:tabnew<CR>` |
| `Alt + ]` / `[` | Next / previous tab or window | Yes | Yes | `gt` / `gT` |
| `Alt + 1..9` | Direct tab / window jump | Yes | Yes | — |
| `Alt + w` | Workspace / session picker | Yes | Yes (`choose-tree`) | — |
| `Alt + b` | Toggle sidebar / status bar | Toggle sidebar | Toggle status bar | — |
| `Alt + g` | **Lazygit** floating popup | Yes (85% modal) | Yes (85% popup) | Yes (Snacks popup) |

*(See [KEYBINDINGS.md](KEYBINDINGS.md) for the complete three-layer doctrine, cross-tool comparison matrix, and full Lazygit cheat sheet.)*

## Recovery

If the terminal feels weird:

```bash
tmux source-file ~/.tmux.conf
./install.sh --config
audit-nvim-keymaps
```

## Agent Configs (Claude Code / Codex)

`./install.sh --config` also deploys sanitized seeds for Claude Code, Codex, Antigravity, and Opencode:

- `config/agents/` → the shared engineering guidance (`ENGINEERING.md`), deployed to **every** agent home below.
- `config/claude/` → `~/.claude/` (`settings.json` plus the shared canon above). Other installers (such as rtk) and `/plugin` write into the same files, so `settings.json` is **merged**, not replaced: repo keys win, every other key is kept, and the pre-merge file is kept as `.bak`. `CLAUDE.md` only gets an `@ENGINEERING.md` import line appended if it lacks one. A key deleted from the repo is not removed from the live file. Same deploy on Windows via `.\install.ps1 -ConfigOnly`.
- `config/codex/` → `~/.codex/` (`AGENTS.md` only gets an `@~/.codex/ENGINEERING.md` import line appended if it lacks one, since rtk adds its own line there; `config.toml` is seeded **only if missing** — Codex appends project trust entries at runtime and a refresh must not wipe them).
- `config/opencode/` → `~/.config/opencode/` (AGENTS.md + the shared canon; `opencode.json` is seed-if-missing only — Opencode writes user prefs into it — and lists the shared docs via its `instructions` array, since Opencode has no `@file` imports).

The only agent plugins installed are this repo's own Claude Code mods,
`config/claude/mods/` → `~/.claude/mods/` (`context-meter`: context usage band
above the prompt; `pretty-tools`: tool calls drawn as blocks with their diff or
output; `cache-timer`: minutes left on the 1-hour prompt cache, under the
prompt). They are registered as the local `my-mods` marketplace through the
`claude` CLI on every refresh, skipped with a warning when `claude` is not on
PATH. Add any other plugins, marketplaces, or hook tools per machine after the
base install. The installer leaves content it does not manage in the agent
homes untouched.

On Linux, the full installer normally executes the vendor-provided Claude and
Codex shell installers. To deploy configs and pinned tools without those two
remote installers, set `DOTFILES_SKIP_AGENT_INSTALLERS=1`.

On Windows, the PowerShell sidecar is deployed to the local
`~\PowerShell\dotfiles.profile.ps1`; `$PROFILE` only contains a small
dot-source wrapper so Known Folder Move/OneDrive is not on the hot path.

**No credentials live in this repo.** Auth comes from machine-local files the
installer scaffolds but never fills:

```bash
~/.secrets/env.sh    # sourced by zsh — machine-local exports
codex login          # Codex OAuth; recreates ~/.codex/auth.json per machine
```

Never commit `auth.json`, `~/.secrets/`, session/history files, or Codex's
`rules/` (accumulated approval state with machine paths) — `.gitignore` guards
all of these defensively.

## Native Windows

On native Windows the installer manages **Alacritty**
(`windows/alacritty/alacritty.toml` → `%APPDATA%lacritty\`, because Alacritty
reads no XDG path on Windows). It uses Catppuccin Macchiato as outer chrome so
the tmux strip inside a WSL shell stays visually distinct. See
[`windows/README.md`](windows/README.md).

## Neovim

Open Neovim and use `<leader>?` or `:VSCodeKeys` for the local VS Code-style key cheat sheet.

After `:Lazy update` / `:MasonUpdate`, snapshot both lockfiles back into the repo with `scripts/sync-nvim-locks` (run `--restore` on a fresh machine before `:Lazy restore`).

On native Windows, Neo-tree refreshes on editor saves instead of keeping OS
file watchers on busy build trees. Press `R` in the explorer to refresh changes
made by external tools. Clangd keeps background indexing and clang-tidy, with
two workers on Windows, lower indexing priority, and error-only logging.
Language servers use Neovim's native configuration API; color previews load
only for supported filetypes instead of delaying the first insert everywhere.
The status line reuses Gitsigns' cached diff counts, and the symbol outline
loads when requested rather than tracking every buffer from startup.

Files detected by Snacks as large (over 1.5 MB or average lines over 1,000 bytes) skip
completion scans, regex syntax and indent guides. Undo remains persistent,
with 1,000 changes for ordinary buffers and 100 for large buffers.

To audit Neovim keymap overlaps after editing:

```bash
audit-nvim-keymaps
```

## Repository Map

- `install.sh`: supported user entry point.
- `installation/`: installer building blocks used by `install.sh`.
- `config/`: source configs copied into `$HOME` and `~/.config`.
- `scripts/`: maintenance helpers installed into `~/.local/bin`.
- `AGENTS.md`: contributor and agent guidance.

## License

[Apache-2.0](LICENSE). You may use, modify, and redistribute this repo; keep
the [NOTICE](NOTICE) file, which credits the author, with any copy or
derivative.
