# Native Windows Support

Standalone native-Windows counterpart of the Linux dotfiles: Alacritty +
PowerShell 7 + the same modern CLI tools and starship prompt as the Linux side.
Alacritty is a plain, fast window in Catppuccin Macchiato; herdr supplies panes
and tabs inside it, and tmux inside a WSL shell keeps its Tokyo Night strip, so
the two layers never blur together. Windows does its job, WSL does its job —
neither side requires the other.

## Install

From PowerShell, in your copy of this repo (clone it or download the ZIP —
whatever you prefer; the installer installs git itself either way):

```powershell
cd dotfiles
.\install.ps1              # tools + configs (Scoop-first)
.\install.ps1 -ConfigOnly  # configs only
.\install.ps1 -DryRun      # print the full package plan; mutate nothing
.\install.ps1 -NoAdmin     # locked-down machine: Scoop only, no UAC
.\install.ps1 -Winget      # winget-first, Scoop fallback
```

(`install.ps1` at the repo root is the Windows counterpart of `./install.sh`;
it forwards to `windows\install.ps1`.)

What it does:

1. **Tools** via Scoop by default: Git, PowerShell 7, Alacritty, JetBrainsMono
   Nerd Font, starship, zoxide, atuin, fzf, bat, fd, eza, ripgrep, jq,
   neovim, lazygit, delta (+ PSFzf module), plus cmake and zig for treesitter
   parser builds, and Python for the agent statuslines (skipped when a real
   interpreter exists; the WindowsApps `python` alias does not count).
   Already-installed packages are skipped
   (and tools already on PATH from a previous winget install are not
   duplicated).

   **Why Scoop-first?** User-scope, no UAC prompts ever, and shims on PATH
   immediately — no shell restart after install. winget is the automatic
   fallback (or pass `-Winget` to invert). On a locked-down box, `-NoAdmin`
   guarantees Scoop-only. Note: run from a *non-elevated* shell — Scoop
   refuses to install as admin.
2. **Configs**: `alacritty.toml` → `%APPDATA%\alacritty\`, the shared Linux
   `starship.toml` → `~\.config\starship.toml` (identical prompt both sides),
   and the dotfiles profile is *injected* into your pwsh 7 `$PROFILE` via a
   dot-source line — your existing profile is never overwritten. A config
   whose content changed is backed up to `<name>.bak` first; unchanged ones are
   left alone.

   **Alacritty's config goes to `%APPDATA%`, not `~\.config`.** On Windows
   Alacritty reads *only* `%APPDATA%\alacritty\alacritty.toml`; the XDG paths it
   uses on Linux and macOS are never consulted.

3. **Agent configs**: sanitized Claude Code / Codex seeds from `config\claude\`
   and `config\codex\` → `~\.claude\` / `~\.codex\`. Credentials never come
   from the repo; run `claude` / `codex login` to authenticate.

## Health check

```powershell
pwsh -File windows\doctor.ps1   # exit 0 = healthy
```

## Keys — one dialect per layer

Alacritty is single-window by design (no tabs or splits) and binds no `Alt`
chords; it only keeps its stock `Ctrl+Shift+C` / `V` copy/paste and adds
`Ctrl+Shift+O` for URL hints. **Alt belongs to the focused muxer**: herdr in
native shells, tmux inside a WSL shell. No modes, no routing.

Inside **herdr** panes, direct Alt chords provide fluid workspace management, plus
the full `ctrl+b` prefix keeps working alongside:

| Key | herdr action |
| :--- | :--- |
| `Alt + h / j / k / l` | Focus pane left / down / up / right |
| `Alt + n` / `Alt + -` | Split side-by-side / split stacked |
| `Alt + z` | Zoom focused pane |
| `Alt + q` | Close pane |
| `Alt + t` | New tab |
| `Alt + ]` / `Alt + [` | Next / previous tab |
| `Alt + 1..9` | Direct tab switch |
| `Alt + w` | Workspace picker |
| `Alt + b` | Toggle sidebar (agents & spaces) |
| `Alt + g` | Lazygit modal popup (85% width/height) |
| `ctrl+b …` | Full prefix keymap (`prefix+?` lists everything) |

## Manual verification checklist

- [ ] Alacritty opens in Catppuccin Macchiato with the JetBrainsMono Nerd Font
- [ ] Nerd Font glyphs render (starship prompt symbols, `ls` icons)
- [ ] Default shell is native pwsh 7 with the dotfiles profile loaded
- [ ] `herdr` starts; `Alt+n` splits, `Alt+t` opens a tab
- [ ] In a WSL shell running tmux, `Alt+T` etc. reach tmux
- [ ] In pwsh 7: `z <dir>`, `cat <file>` (bat), `ls`/`ll` (eza icons) work
- [ ] `Ctrl+R` shell history (atuin; PSFzf history when atuin is absent) / `Ctrl+T` fuzzy files (PSFzf)
- [ ] Prompt looks identical to the Linux starship prompt
- [ ] `nvim` opens with the shared config; lazy.nvim installs plugins on first launch

## Notes

- **Update through the installation owner.** For Scoop packages, run
  `scoop update`, then `scoop update <package>` (for example `neovim`).
  Avoid application self-updaters for these packages: they can replace a
  Scoop launcher with a full binary and leave Scoop's version record stale.
  Use npm for npm-installed OpenCode2 and the standalone updater for Herdr.
- **MSYS2 and WSL are different environments.** Run `install.sh` inside a
  supported Linux/WSL distribution, not through an arbitrary Windows `bash`
  command. Vendor toolchain directories in Windows PATH can also override
  MSYS2's `find`, `make`, and other utilities; use the MSYS2 login shell for
  MSYS2 work and retain dedicated toolchain environments for embedded builds.

- Everything targets **PowerShell 7** (`pwsh`), not Windows PowerShell 5.1.
- Alacritty starts **native pwsh 7**; run `wsl` from it when you need Linux.
  Windows never depends on WSL being present.
- **The PowerShell profile is local, not OneDrive-backed.** The installer
  deploys `~\PowerShell\dotfiles.profile.ps1` and injects only a small
  dot-source line into the PowerShell profile. This avoids Known Folder Move
  filter overhead on every shell startup.
- **PowerShell performance:** interactive sessions retain Starship, Atuin,
  zoxide and lazy PSFzf bindings. Tool discovery caches both installed and
  missing applications without probing PowerShell modules. Init scripts in
  `~/.cache/dotfiles/` refresh when the executable or init options change.
  The derived `starship-windows.toml` omits the already-hidden dirty module
  from the prompt format, avoiding its `sh` process even when `when` is false;
  the shared source and Git branch/state display are preserved. An explicit
  `STARSHIP_CONFIG` override takes precedence. Redirected child shells skip
  the prompt and interactive history hooks; z/zi and CLI aliases remain usable.
  The selected Git for Windows installation supplies `EXEPATH` when unset,
  avoiding gitoxide's extra Git process on every prompt while preserving its
  configuration. Existing hints and unsupported installation layouts are left alone.
- **`~\.wslconfig`** is seeded once (never overwritten) with WSL2 memory/disk
  guardrails (`autoMemoryReclaim=gradual`, `sparseVhd=true`); run
  `wsl --shutdown` when convenient to apply.
- **Neovim config location**: Windows Neovim reads `%LOCALAPPDATA%\nvim`, not
  `~/.config/nvim`; the installer deploys the shared `config/nvim` there.
  First launch downloads plugins (pinned by `lazy-lock.json`) — needs network.
  Treesitter compiles parsers and needs a C compiler on Windows — the
  installer ships zig (compiler) and cmake for this; if you see parser build
  errors anyway, `winget install zig.zig` (or LLVM) and restart nvim.
  Copilot needs Node.js: `winget install OpenJS.NodeJS.LTS`.
