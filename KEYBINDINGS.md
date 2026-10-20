# Unified Keybinding Architecture (SSS-Tier)

This document specifies the cross-platform, conflict-free keybinding architecture deployed across this repository. It covers **Herdr** (primary terminal workspace manager), **Tmux**, **Neovim**, **Lazygit**, and the outer terminal emulator (**Alacritty** on Windows).

---

## 1. The Three-Layer Separation Doctrine

To guarantee that keybindings never collide across tools or operating systems, all chords are strictly partitioned into three independent layers:

```
┌─────────────────────────────────────────────────────────────┐
│ LAYER 1: OUTER TERMINAL (Alacritty on Windows)              │
│ Owns: stock Ctrl + Shift chords only (copy, paste, hints)   │
│ Scope: the window itself; no tabs or splits                 │
└──────────────────────────────┬──────────────────────────────┘
                               │ (passes through Alt & bare keys)
┌──────────────────────────────▼──────────────────────────────┐
│ LAYER 2: WORKSPACE MUXER (Herdr / Tmux)                     │
│ Owns: Direct Alt + <Key>  (and fallback Ctrl+b prefix)      │
│ Scope: Mux panes, workspaces, mux tabs, floating popups      │
└──────────────────────────────┬──────────────────────────────┘
                               │ (passes through bare keys & Ctrl chords)
┌──────────────────────────────▼──────────────────────────────┐
│ LAYER 3: EDITOR & APPS (Neovim / Lazygit / Shells)          │
│ Owns: Bare keys (h,j,k,l, 1-5, q, space), Leader, Ctrl      │
│ Scope: Buffer editing, git staging, command line            │
└─────────────────────────────────────────────────────────────┘
```

1. **Outer Terminal (Layer 1)**:
   - Keeps only its stock **`Ctrl + Shift + <Key>`** chords; panes and tabs belong to the muxer.
   - Never binds `Alt` chords.
   - On macOS, set the terminal's left Option key to send Meta so Alt chords reach the muxer (see `README.md`).

2. **Workspace Manager / Muxer (Layer 2)**:
   - Exclusively uses **`Alt + <Key>`** for direct, zero-friction execution.
   - Eliminates OS collisions (e.g., `Alt + Space` is replaced with `Alt + w` to avoid Windows System Menu activation).
   - Multiplexer prefix mode (`Ctrl + b`) remains active as a secondary fallback.

3. **Editor & Apps (Layer 3)**:
   - Owns bare alphanumeric keys (`h`, `j`, `k`, `l`, `w`, `q`, numbers), `<leader>` chords, and standard `Ctrl` keys (`<C-r>`, `<C-d>`, `<C-u>`).
   - None of Lazygit's or Neovim's default editing keys are hijacked by the outer layers.

---

## 2. Universal Navigation Matrix

Every workspace manager and editor in this repository shares identical chords for identical actions:

| Action | **Herdr** (Primary) | **Tmux** (Muxer) | **Neovim** (Editor) |
| :--- | :--- | :--- | :--- |
| **Focus Left** | `Alt + h` | `Alt + h` | `Alt + h` / `Alt + ←` |
| **Focus Down** | `Alt + j` | `Alt + j` | `Alt + j` / `Alt + ↓` |
| **Focus Up** | `Alt + k` | `Alt + k` | `Alt + k` / `Alt + ↑` |
| **Focus Right** | `Alt + l` | `Alt + l` | `Alt + l` / `Alt + →` |
| **Split Side-by-Side** | `Alt + n` | `Alt + n` | `<C-w>v` |
| **Split Stacked** | `Alt + -` | `Alt + -` | `<C-w>s` |
| **Zoom / Fullscreen** | `Alt + z` | `Alt + z` | `<C-w>o` |
| **Close Pane** | `Alt + q` | `Alt + q` | `:q<CR>` |
| **New Tab** | `Alt + t` | `Alt + t` | `:tabnew<CR>` |
| **Next Tab / Window** | `Alt + ]` | `Alt + ]` | `gt` / `]b` |
| **Prev Tab / Window** | `Alt + [` | `Alt + [` | `gT` / `[b` |
| **Jump to Tab 1..9** | `Alt + 1..9` | `Alt + 1..9` | — |
| **Workspace / Session** | `Alt + w` | `Alt + w` (`choose-tree`) | — |
| **Toggle Sidebar / Bar** | `Alt + b` | `Alt + b` | — |
| **Lazygit Popup** | `Alt + g` / `prefix + Alt + g` | `Alt + g` / `prefix + Alt + g` | `Alt + g` / `<leader>gg` |

Tmux mirrors Herdr's `[keys]` table chord for chord and binds no other direct chords, so anything else (e.g. `Alt + Arrow`, `Shift + Arrow`) reaches the app in the pane under either muxer.

---

## 3. Lazygit Universal Workflow

Lazygit is configured with the Tokyo Night Storm palette (`config/lazygit/config.yml`) and is callable anywhere:

- **Invocation**: Press **`Alt + g`** in Herdr, Tmux, or Neovim (or type **`lg`** in any shell).
- **Dismissal**: Press **`q`** inside Lazygit to close the modal popup and return directly to your previous prompt or buffer.
- **Editor Integration**: Pressing **`e`** opens the selected file directly in Neovim (`$EDITOR="nvim"`).

### Core Lazygit Keybindings

#### Panel Navigation
| Key | Context | Action |
| :--- | :--- | :--- |
| `1` | Global | Jump to **Status** panel |
| `2` | Global | Jump to **Files** panel |
| `3` | Global | Jump to **Branches** panel |
| `4` | Global | Jump to **Commits** panel |
| `5` | Global | Jump to **Stash** panel |
| `h` / `l` or `←` / `→` | Global | Switch between side panel and main diff viewer |
| `j` / `k` or `↓` / `↑` | Global | Move down / up in any list |
| `[` / `]` | Panel | Switch tabs within current panel (e.g., Submodules, Remotes, Reflog) |
| `<Tab>` | Global | Toggle focus between side panel and diff viewer |
| `J` / `K` or `<C-d>` / `<C-u>` | Global | Scroll diff view up / down without losing file selection |
| `?` or `x` | Global | Open interactive keybinding menu / cheatsheet |
| `q` | Global | Quit Lazygit |

#### Staging & Committing (Files Panel `2`)
| Key | Action |
| :--- | :--- |
| `<Space>` | Stage / unstage selected file |
| `a` | Stage all / unstage all |
| `<Enter>` | Enter line/hunk staging mode (drill into diff) |
| `v` | Visual hunk selection mode in diff |
| `c` | Commit staged changes (opens inline commit prompt) |
| `C` | Commit using Neovim (`$EDITOR`) |
| `A` | Amend last commit |
| `s` | Stash changes |
| `d` | Discard changes to selected file (with safety prompt) |
| `e` | Edit file in Neovim |

#### Branches (Panel `3`)
| Key | Action |
| :--- | :--- |
| `<Space>` | Checkout selected branch |
| `n` | Create new branch |
| `c` | Checkout branch by name |
| `r` | Rebase current branch onto selected branch |
| `M` | Merge selected branch into current branch |
| `f` | Fast-forward selected branch |
| `d` | Delete selected branch |

#### Commits & Interactive Rebase (Panel `4`)
| Key | Action |
| :--- | :--- |
| `s` | Squash selected commit down |
| `r` | Reword / rename commit |
| `R` | Rename commit with Neovim |
| `f` | Mark commit as fixup |
| `F` | Create fixup commit |
| `<C-j>` / `<C-k>` | Move commit down / up in git history |
| `d` | Drop commit |
| `t` | Revert commit |
| `<C-r>` | **Interactive rebase** of the last N commits (dotfiles custom shortcut) |
| `g` | Reset options (soft, mixed, hard reset to selected commit) |

#### Push & Sync
| Key | Action |
| :--- | :--- |
| `p` | Pull changes from remote |
| `P` | **Push with lease** (`git push --force-with-lease` custom command) |
| `z` / `<C-z>` | Undo / redo last git action |

---

## 4. Neovim & Smart Split Navigation

- **Vim-Aware Split Navigation**: In Tmux, `Alt + h/j/k/l` (and `Alt + Arrows` inside Neovim) move between Neovim windows and Tmux panes via `vim-tmux-navigator`: at the edge of a Neovim window, the chord jumps into the adjacent Tmux pane. Herdr takes `Alt + h/j/k/l` itself, so there they always move between Herdr panes; use `Alt + Arrows` or `<C-w>` for Neovim splits.
- **No Arrow Penalties**: Native arrow keys (`<Up>`, `<Down>`, `<Left>`, `<Right>`) are fully functional in all modes for fast cursor positioning, terminal history, and visual selection.
- **Internal Window Management**: Standard `<C-w>` chords (`<C-w>v` vertical split, `<C-w>s` horizontal split, `<C-w>q` close, `<C-w>o` zoom) remain fully supported.
- **Snacks Keymaps**:
  - `<leader><space>`: Smart Find Files
  - `<leader>,`: Buffer Picker
  - `<leader>sg`: Ripgrep Search
  - `<leader>gg` or `Alt + g`: Lazygit
  - `<leader>gb`: Git blame line

---

## 5. Cross-Platform Gotchas & Implementation Notes

1. **Windows Alt+Space Collision**:
   - On Windows, `Alt + Space` is intercepted by the OS to open the window control menu (Restore, Move, Size, Minimize, Maximize, Close).
   - This repo binds workspace/session selection to **`Alt + w`** across all tools, completely avoiding the Windows OS intercept.

2. **macOS Option Key Handling**:
   - On macOS, terminal emulators by default treat the Option key as a character accent composer (e.g. `Alt+n` typing `~`).
   - Make left Option send Meta/Alt chords and keep right Option for special characters; for iTerm2 / Terminal.app see `README.md`.

3. **Herdr Key Syntax**:
   - Herdr's `[keys]` table requires individual string values (e.g. `focus_pane_left = "alt+h"`). Passing an array breaks the parser and drops custom keybindings.
   - Modal popups are declared using `[[keys.command]]` with `type = "popup"`.

4. **BOM & Line Endings**:
   - All PowerShell `.ps1` files in this repo must retain their UTF-8 BOM, CRLF line endings, and ASCII strings (verified via `tests/windows_preflight.ps1`).
   - All JSON configuration files (e.g. `settings.json`) must NOT include a UTF-8 BOM (`\ufeff`) to prevent parser failures.
