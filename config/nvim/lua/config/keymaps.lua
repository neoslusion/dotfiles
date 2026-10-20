-- Compatibility wrapper for keymap setting
local keymap = vim.keymap.set

local opts = { noremap = true, silent = true }                               -- Common options: non-recursive and silent mappings

-- Motion layer:
--   hjkl is the primary cursor motion, with stock arrows available as natural fallbacks.
--   Alt+Arrow and Alt+HJKL are reserved for pane/split navigation (see tmux-navigator.lua).

-- (Removed leader-based window nav: Alt+Arrow now handles pane/split navigation seamlessly.)

-- Move lines: use Visual-mode J/K (defined below). Alt+Up/Down is intentionally
-- NOT used here -- it belongs to tmux-aware pane navigation, and double-binding it
-- to move-line silently broke whichever mapping loaded last.

-- (Removed <C-z>/<C-y> undo/redo: use native u / <C-r>. Restores <C-z> = suspend, <C-y> = scroll up.)

-- VS Code-like: Sidebar
-- <leader>e is the primary binding. <C-b is deliberately NOT bound anywhere:
-- herdr owns the ctrl+b prefix (tmux heritage), so it never reaches Neovim.

-- VS Code-like: New File (Ctrl+N) -- normal mode only: insert-mode <C-n> is
-- owned by nvim-cmp (completion menu nav), see plugins/completion.lua.
keymap("n", "<C-n>", ":enew<CR>", opts)                                      -- Ctrl+N: create new buffer

-- VS Code-like: File Search (Ctrl+P) -- normal mode only; same insert-mode
-- ownership rule (<C-p> selects the previous completion item).
-- Optimized: Using Snacks picker for near-instant performance
keymap("n", "<C-p>", function() Snacks.picker.files() end, opts)

-- Search in Files - WSL compatible
-- Note: Ctrl+Shift+F doesn't work in terminals, using leader-based alternative
keymap("n", "<leader>fw", function() Snacks.picker.grep_word() end, opts)    -- <Leader>fw: find word under cursor

-- Resize windows - WSL compatible (using leader-based mappings)
-- Note: Ctrl+Arrow keys often don't work in WSL terminals
keymap("n", "<leader>=", ":resize +2<CR>", opts)                             -- <Leader>=: increase window height
keymap("n", "<leader>-", ":resize -2<CR>", opts)                             -- <Leader>-: decrease window height
keymap("n", "<leader>>", ":vertical resize +2<CR>", opts)                    -- <Leader>>: increase window width
keymap("n", "<leader><", ":vertical resize -2<CR>", opts)                    -- <Leader><: decrease window width
-- (Removed duplicate <leader>r* resize set: use <leader>= / - / > / < above, or tmux prefix + Alt+Arrow.)

-- Buffer navigation: H/L (bufferline) and [b / ]b are THE buffer cyclers.
-- Tab/S-Tab were removed deliberately: normal-mode Tab shares a byte code
-- with <C-i>, so binding it silently killed jumplist-forward navigation.
-- (Removed <leader>bn / <leader>bp: H/L and [b/]b already cycle buffers.)
keymap("n", "<leader>bD", function() Snacks.bufdelete.delete({ force = true }) end, opts) -- <Leader>bD: force delete current buffer

-- Stay in indent mode
keymap("v", "<", "<gv", opts)                                                -- Visual mode <: shift-left and keep selection active
keymap("v", ">", ">gv", opts)                                                -- Visual mode >: shift-right and keep selection active

-- Move text up and down
keymap("v", "J", ":m '>+1<CR>gv=gv", opts)                                   -- Visual J: move selected lines down, reselect, reindent
keymap("v", "K", ":m '<-2<CR>gv=gv", opts)                                   -- Visual K: move selected lines up, reselect, reindent

-- Better paste
keymap("v", "p", '"_dP', opts)                                               -- Visual p: paste without overwriting the default register (use black hole)

-- Clear search highlighting
keymap("n", "<leader>chk", ":nohlsearch<CR>", opts)                          -- <Leader>chk: clear search highlights (remapped from <leader>h)

-- Better line joining
keymap("n", "J", "mzJ`z", opts)                                              -- Normal J: mark cursor (m z), join lines (J), return to mark (`z)

-- Center search results
keymap("n", "n", "nzzzv", opts)                                              -- n: next match, center line (zz), open folds if needed (zv)
keymap("n", "N", "Nzzzv", opts)                                              -- N: previous match, center line (zz), open folds if needed (zv)

-- File operations
keymap("n", "<leader>W", ":w ", { noremap = true })                          -- <Leader>W: save as (prompts for filename)
-- (Removed <leader>n new-file: duplicate of <C-n>; use <C-n> or :enew.)

-- Split windows
keymap("n", "<leader>sv", ":vsplit<CR>", opts)                               -- <Leader>sv: split window vertically
keymap("n", "<leader>sh", ":split<CR>", opts)                                -- <Leader>sh: split window horizontally

-- Quickfix list navigation (vim-idiomatic bracket pairs, matching [d/]d for diagnostics)
keymap("n", "[q", ":cprev<CR>", opts)                                        -- [q: previous quickfix item
keymap("n", "]q", ":cnext<CR>", opts)                                        -- ]q: next quickfix item

-- save file
keymap({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", opts)

-- Literal search: search without regex special chars ([, ], *, ., etc.)
-- Use <leader>/ for literal search (finds exact text including brackets)
keymap("n", "<leader>/", "/\\V", { noremap = true, desc = "Literal Search" })

-- VS Code Specific Keymaps (Terminal-Safe Leader Variants)
-- Terminal emulators swallow Ctrl+Shift / Alt+Shift combos, so these live on <leader> only.

-- Command Palette -> <leader>cp (terminal-safe; <C-S-p> rarely survives the terminal)
keymap("n", "<leader>cp", "<cmd>Telescope commands<CR>", opts)

-- Search & Replace in Project -> <leader>fs (terminal-safe; <C-S-f> rarely survives the terminal)
keymap("n", "<leader>fs", function() require("grug-far").open() end, opts)

-- Format Document -> <leader>cf (registered by conform.nvim; <A-S-f> rarely survives the terminal)

-- Go to Symbol in File -> <leader>cs (terminal-safe; <C-S-o> rarely survives the terminal)
keymap("n", "<leader>cs", function() Snacks.picker.lsp_symbols() end, opts)

-- Toggle Line Comment (Ctrl+/)
-- Note: Most terminals translate `Ctrl+/` into the raw escape code `<C-_>`. We map both to Neovim's native `gcc`/`gc`.
keymap("n", "<C-/>", "gcc", { remap = true, desc = "Toggle Comment" })
keymap("v", "<C-/>", "gc", { remap = true, desc = "Toggle Comment" })
keymap("n", "<C-_>", "gcc", { remap = true, desc = "Toggle Comment" })
keymap("v", "<C-_>", "gc", { remap = true, desc = "Toggle Comment" })

-- (Removed <C-f> find-in-file: use `/` to search. <C-f> returns to native page-forward.)
-- Buffer-line fuzzy search still available via <leader>/ (grep) and Snacks pickers.

-- (Removed insert-mode <F2> rename: use normal-mode <F2> or <leader>rn instead.)

local function vscode_keys()
  local lines = {
    "VS Code -> Neovim cheat sheet",
    "",
    "Terminal/tmux-safe primary bindings:",
    "  <leader>e        Explorer",
    "  <leader>ff       Go to file",
    "  <leader>cp       Command palette",
    "  <leader>fs       Search and replace in project",
    "  <leader>/        Search text in project",
    "  <leader>cf       Format document",
    "  <F2>             Rename symbol",
    "  <leader>cs       Symbols in file/workspace",
    "  <leader>gg       Git UI",
    "  <leader>tt       Run current test file",
    "",
    "Compatibility bindings that may depend on your terminal:",
    "  <C-p>            Go to file",
    "  <C-s>            Save",
    "  <C-/>            Toggle comment",
    "  /                Search in current file (native)",
    "",
    "Layer ownership:",
    "  Terminal: stock Ctrl+Shift (copy, paste)",
    "  Herdr/tmux: Alt muxing (panes, tabs, zoom)",
    "  Neovim: leader, function keys, plain Ctrl content actions",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.min(72, vim.o.columns - 4),
    height = math.min(#lines + 2, vim.o.lines - 4),
    row = 2,
    col = math.floor((vim.o.columns - math.min(72, vim.o.columns - 4)) / 2),
    border = "rounded",
    title = " VSCodeKeys ",
  })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
end

vim.api.nvim_create_user_command("VSCodeKeys", vscode_keys, {})
keymap("n", "<leader>?", vscode_keys, vim.tbl_extend("force", opts, { desc = "VS Code keymap help" }))
