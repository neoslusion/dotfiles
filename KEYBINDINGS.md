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
| **Split Side-by-Side** | `Alt + n` | `Alt + n` | `sv` |
| **Split Stacked** | `Alt + -` | `Alt + -` | `ss` |
| **Zoom / Fullscreen** | `Alt + z` | `Alt + z` | `<C-w>o` |
| **Close Pane** | `Alt + q` | `Alt + q` | `:q<CR>` |
| **New Tab** | `Alt + t` | `Alt + t` | `te` |
| **Next Tab / Window** | `Alt + ]` | `Alt + ]` | `<Tab>` |
| **Prev Tab / Window** | `Alt + [` | `Alt + [` | `<S-Tab>` |
| **Jump to Tab 1..9** | `Alt + 1..9` | `Alt + 1..9` | — |
| **Workspace / Session** | `Alt + w` | `Alt + w` (`choose-tree`) | — |
| **Toggle Sidebar / Bar** | `Alt + b` | `Alt + b` | — |
| **Lazygit Popup** | `Alt + g` / `prefix + Alt + g` | `Alt + g` / `prefix + Alt + g` | `;g` |

Tmux mirrors Herdr's `[keys]` table chord for chord and binds no other direct chords, so anything else (e.g. `Alt + Arrow`, `Shift + Arrow`) reaches the app in the pane under either muxer.

---

## 3. Lazygit Universal Workflow

Lazygit is configured with a Solarized palette (`home/dot_config/lazygit/config.yml`) and is callable anywhere:

- **Invocation**: Press **`Alt + g`** in Herdr or Tmux, **`;g`** in Neovim (or type **`lg`** in any shell).
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
| `<C-r>` | **Interactive rebase** of the last N commits (dotfiles custom command, default 5) |
| `<C-t>` | **Annotated tag** on the selected commit (dotfiles custom command) |
| `g` | Reset options (soft, mixed, hard reset to selected commit) |

#### Push & Sync
| Key | Action |
| :--- | :--- |
| `p` | Pull changes from remote |
| `P` | Push (stock; asks before force-pushing a rejected push) |
| `z` / `<C-z>` | Undo / redo last git action |

---

## 4. Neovim

Defined in `home/dot_config/nvim/lua/config/keymaps.lua` and
`lua/plugins/keymaps.lua`. **Leader is `Space`.** `;`, `s` and `\` are plain
normal-mode prefixes. Check for duplicates with
`python3 home/dot_local/bin/audit_nvim_keymaps.py home/dot_config/nvim`.

- **Split Navigation**: In Tmux, `Alt + h/j/k/l` and `Alt + Arrows` move between Neovim windows and Tmux panes via `vim-tmux-navigator`: at the edge of a Neovim window, the chord jumps into the adjacent Tmux pane. Herdr takes `Alt + h/j/k/l` itself, so there they always move between Herdr panes; use `sh/sj/sk/sl` for Neovim splits.
- Arrow keys and stock `<C-w>` chords keep working.

#### Files & Search
| Key | Action |
| :--- | :--- |
| `;f` | Find files |
| `;r` | Live grep |
| `;;` | Resume the last picker |
| `\\` | Buffer list (jumps to the window if the buffer is already open) |
| `;e` | Diagnostics |
| `;n` | Notification history |
| `sf` | Oil file explorer (float). Inside: `h` parent dir, `q` close; edit the listing and `:w` to create, rename or delete files |

#### Windows & Tabs
| Key | Action |
| :--- | :--- |
| `ss` / `sv` | Split stacked / side-by-side |
| `sh` `sj` `sk` `sl` | Move to the split left / down / up / right |
| `Alt + h/j/k/l`, `Alt + Arrows` | Move between splits and Tmux panes |
| `te` | New tab |
| `<Tab>` / `<S-Tab>` | Next / previous tab |

#### LSP
| Key | Action |
| :--- | :--- |
| `gd` / `gD` / `gy` / `gI` | Definition / declaration / type definition / implementation |
| `gr` | References |
| `K` | Hover |
| `gK`, `<C-k>` (insert) | Signature help |
| `<C-j>` | Next diagnostic (with float) |
| `]]` / `[[` | Next / previous reference of the word under the cursor |
| `;c` | Incoming calls |
| `<leader>ca` | Code action (normal and visual) |
| `<leader>cr` | Rename symbol |
| `<leader>cR` | Rename file (updates imports) |
| `<leader>cl` | LSP info |
| `<leader>f` | Format buffer or selection |

#### Git
| Key | Action |
| :--- | :--- |
| `;g` | Lazygit |
| `;h` | Git diff hunks picker |
| `<leader>gb` / `<leader>gB` | Blame line / blame buffer |
| `<leader>go` | Open the line's file at the commit that last changed it (new tab) |
| `<leader>gs` | Stage buffer (unstage if nothing left to stage) |
| `<leader>gh` | Stage hunk |
| `<leader>gd` | Toggle inline diff overlay |
| `]c` / `[c` | Next / previous change |
| `<leader>dv` | Side-by-side diff view |
| `<leader>dh` / `<leader>dH` | File history / repo history |

#### Harpoon
| Key | Action |
| :--- | :--- |
| `<leader>a` | Pin the current file |
| `<leader>h` | Harpoon menu (reorder or delete; saves on close) |
| `<leader>1` … `<leader>5` | Jump to pinned file 1–5 |

#### Editing (differs from stock Vim)
| Key | Action |
| :--- | :--- |
| `x` | Delete a character without touching the yank register |
| `<leader>d` / `<leader>D` | Delete / delete to end of line without touching the yank (normal and visual) |
| `<leader>c` / `<leader>C` | Change / change to end of line without touching the yank (normal and visual) |
| `<leader>p` / `<leader>P` | Paste the last yank after / before, even after a delete |
| `dw` | **Delete the word before the cursor** (use `de` / `daw` to delete forward) |
| `+` / `-` | Increment / decrement the number under the cursor |
| `<C-a>` | Select the whole buffer (not increment) |
| `<leader>o` / `<leader>O` | New line below / above without comment continuation |
| `<C-m>` | Jump forward in the jumplist |
| `<` / `>`, `<Tab>` / `<S-Tab>` (visual) | Indent and keep the selection |
| `<leader>yf` / `<leader>yp` | Yank relative / absolute path with line number |
| `<leader>cc` (visual) | Copy the selection as a Markdown code block |
| `<leader>bd` | Delete hidden buffers |

#### Completion (blink.cmp, `enter` preset)
| Key | Action |
| :--- | :--- |
| `<CR>` | Accept |
| `<C-n>` / `<C-p>`, `<Up>` / `<Down>` | Next / previous item |
| `<C-Space>` | Open menu / docs |
| `<C-e>` | Close menu |
| `<C-b>` / `<C-f>` | Scroll docs |
| `<Tab>` / `<S-Tab>` | Next / previous snippet placeholder |

On the `:` command line the menu opens automatically with ghost text;
`<Left>` / `<Right>` still move the cursor. Brackets auto-close (mini.pairs).
Lua and shell files format on save.

#### Gotchas
- Most terminals send the same code for `<CR>` and `<C-m>`, so `Enter` in normal mode jumps forward in the jumplist.
- `<leader>c` and `<leader>d` are prefixes of longer maps (`<leader>ca`, `<leader>dv`, ...), so alone they wait for `timeoutlen` before acting.

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
   - Plain PowerShell `.ps1` files keep their UTF-8 BOM, CRLF line endings, and ASCII strings (`.gitattributes`); `*.ps1.tmpl` scripts are LF without a BOM.
   - All JSON configuration files (e.g. `settings.json`) must NOT include a UTF-8 BOM (`\ufeff`) to prevent parser failures.
