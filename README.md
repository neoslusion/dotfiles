# Dotfiles

Zsh, tmux, Neovim and agent configs for **Debian/Ubuntu (including WSL), Arch,
Fedora, macOS and native Windows**, managed by [chezmoi](https://chezmoi.io).
Everything installs at its latest version.

## Contents

- **Shell:** zsh with Oh My Zsh, starship, atuin, zoxide, fzf; PowerShell 7 on Windows
- **Terminal:** Alacritty (Windows, Solarized Dark), herdr panes and tabs, tmux in WSL/Linux
- **Editor:** Neovim with built-in `vim.pack`, solarized-osaka, clangd / rust-analyzer / pyright
- **Git:** lazygit and delta
- **Tools and runtimes:** mise on Linux and macOS (python, rust, uv, every CLI tool); Scoop on Windows
- **Agents:** Claude Code, Codex, Antigravity and opencode settings, plus this repo's Claude Code mods

## Install

Install chezmoi with your package manager (`brew install chezmoi`,
`scoop install chezmoi`, `pacman -S chezmoi`, ...), then:

```bash
chezmoi init --apply neoslusion/dotfiles
```

Or from an existing clone, so the checkout you edit is what gets applied:

```bash
chezmoi init --apply --source ~/sandboxes/dotfiles
```

On Windows run this from a **non-elevated** pwsh 7 (Scoop refuses an elevated
shell), then restart the terminal once so `XDG_CONFIG_HOME` takes effect.

What `apply` does:

1. Writes the files under `home/` into your home directory.
2. Runs `home/.chezmoiscripts/`, each only when its input changed:
   - **install-packages:** the base packages from `home/.chezmoidata/packages.yaml`
     (apt, pacman, dnf, Homebrew or Scoop), then on Linux and macOS mise and
     the tools in `~/.config/mise/config.toml`. Sets delta as git's pager.
   - **windows-setup:** sets `XDG_CONFIG_HOME=~\.config` so Windows Neovim and
     lazygit read the same `~/.config` as Unix, and adds one line to
     `$PROFILE` that loads `~\PowerShell\dotfiles.profile.ps1`.
   - **register-claude-mods:** registers `~/.claude/mods` as the `my-mods`
     marketplace through the `claude` CLI (skipped when `claude` is missing).
3. Clones Oh My Zsh, its plugins and TPM, and the JetBrainsMono Nerd Font on
   Linux (`home/.chezmoiexternal.toml.tmpl`).

The Claude Code and Codex CLIs are not installed for you: use their own installers.

## Everyday

```bash
chezmoi diff               # what apply would change
chezmoi apply              # deploy the repo
chezmoi apply ~/.config/nvim   # one target only
chezmoi re-add             # pull live edits of managed files back into the repo
chezmoi update             # git pull + apply
mise upgrade               # update the Unix tools; Windows: scoop update *
```

Run `pre-commit install` once per clone: it runs gitleaks on every commit.

## How files are managed

- **Plain files** (`dot_config/nvim/...`) are overwritten on apply.
- **`create_` files** are written only when missing, because the tool edits
  them at runtime: herdr's `config.toml`, Codex `config.toml`, opencode's
  `opencode.json`, Antigravity's `mcp.json`, `~/.wslconfig`, and the
  `~/.secrets/env.sh` / `env.ps1` scaffolds.
- **`modify_` files** are merged into the live file, because rtk, `/plugin` and
  the agents write to them too:
  - `~/.claude/settings.json` and Antigravity's `settings.json`: repo keys win,
    nested objects merge, other keys are kept. A key deleted from the repo is
    not removed from the live file. Claude's `permissions` lists deny force
    pushes and ask before `git push` or `rm -rf`; they replace the live lists,
    so add extra rules to the repo copy.
  - `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` and `~/.zprofile` only get
    their import or source line appended when it is missing.
- `ENGINEERING.md` (shared engineering guidance) is deployed to every agent
  home from one copy in `home/.chezmoitemplates/`.

**No credentials live in this repo.** Put machine-local exports in
`~/.secrets/env.sh` (zsh) or `~\.secrets\env.ps1` (pwsh), and log in with
`claude` / `codex login`.

## Claude Code mods

`home/dot_claude/mods/` deploys to `~/.claude/mods/`: `context-meter` (context
and usage-limit band above the prompt), `pretty-tools` (tool calls drawn as
blocks with their diff or output), `cache-timer` (minutes left on the prompt
cache) and `delegation-workers` (live agent-delegation worker tasks).

## Neovim

Plugins come from Neovim's built-in `vim.pack` (the first launch asks to
install them); update with `:lua vim.pack.update()`. Mason installs clangd,
rust-analyzer and, when `npm` is available, pyright. Format on save runs only
for filetypes with a formatter (stylua, shfmt); `<leader>f` formats manually.
Clangd finds `compile_commands.json` in `Build/`, `build/`, `out/build/` and
`cmake-build-*`. Machine-local plugins go in `lua/plugins/local.lua`, which git
ignores.

On Windows, treesitter builds parsers with zig, and pyright needs Node.js
(`winget install OpenJS.NodeJS.LTS`).

## Keys

One set of Alt chords across herdr, tmux and Neovim:

| Key | Action |
| :--- | :--- |
| `Alt + h / j / k / l` | Focus pane or Neovim split |
| `Alt + n` / `Alt + -` | Split side-by-side / stacked |
| `Alt + z` | Zoom pane |
| `Alt + q` | Close pane |
| `Alt + t` | New tab / window |
| `Alt + ]` / `[`, `Alt + 1..9` | Next / previous / direct tab |
| `Alt + w` | Workspace / session picker |
| `Alt + g` | Lazygit popup |

See [KEYBINDINGS.md](KEYBINDINGS.md) for the full list.

## Notes

- **macOS terminal:** set Option to act as Meta (iTerm2: Profiles > Keys >
  Left Option Key `Esc+`; Terminal.app: Use Option as Meta key) so the Alt
  chords work.
- **tmux** is installed but does not auto-attach; `DOTFILES_TMUX=1` (for
  example in `~/.secrets/env.sh`) restores the auto-attached `Main` session.
- **Windows PowerShell profile** stays on the local disk: `$PROFILE` (often in
  OneDrive-redirected Documents) only dot-sources
  `~\PowerShell\dotfiles.profile.ps1`.
- **Windows updates:** use `scoop update`, not an app's own self-updater,
  which can replace Scoop's launcher. `herdr update` updates herdr.

## Repository layout

- `.chezmoiroot`: makes `home/` the chezmoi source; everything else here is repo tooling.
- `home/`: the files deployed to `$HOME`, in chezmoi naming (`dot_`, `create_`, `modify_`).
- `home/.chezmoidata/packages.yaml`: package lists per platform.
- `home/.chezmoiscripts/`: the install and setup scripts.
- `home/.chezmoitemplates/`: shared sources (settings, ENGINEERING.md, herdr seed).
- `.github/workflows/ci.yml`: gitleaks, shellcheck, and a full `chezmoi init --apply` on Ubuntu, macOS, Arch, Fedora and Windows.

## License

[Apache-2.0](LICENSE). You may use, modify, and redistribute this repo; keep
the [NOTICE](NOTICE) file, which credits the author, with any copy or
derivative.
