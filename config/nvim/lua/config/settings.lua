-- Set leader key
vim.g.mapleader = " "                                                        -- Global <Leader> set to space
vim.g.maplocalleader = "\\"                                                   -- Local <LocalLeader> set to backslash

-- Disable netrw (use neo-tree instead)
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrw = 1

-- Hide deprecation warnings
vim.g.deprecation_warnings = false

-- Basic Neovim Settings
local opt = vim.opt

-- General
opt.mouse = "a"                    -- Enable mouse support
opt.clipboard = "unnamedplus"      -- Use system clipboard
opt.swapfile = false              -- Disable swap file
opt.completeopt = "menu,menuone,noselect"

-- Sync clipboard between OS and Neovim.
-- Schedule this after UIEnter to avoid startup lag
vim.schedule(function()
  if vim.fn.has("wsl") == 1 then
    vim.g.clipboard = {
      name = "WslClipboard",
      copy = {
        ["+"] = "win32yank.exe -i --crlf",
        ["*"] = "win32yank.exe -i --crlf",
      },
      paste = {
        ["+"] = "win32yank.exe -o --lf",
        ["*"] = "win32yank.exe -o --lf",
      },
      cache_enabled = 1,
    }
  elseif vim.fn.has("win32") == 1 then
    if vim.fn.executable("win32yank.exe") == 1 then
      vim.g.clipboard = {
        name = "win32yank",
        copy = {
          ["+"] = "win32yank.exe -i --crlf",
          ["*"] = "win32yank.exe -i --crlf",
        },
        paste = {
          ["+"] = "win32yank.exe -o --lf",
          ["*"] = "win32yank.exe -o --lf",
        },
        cache_enabled = 1,
      }
    end
  end
end)

-- WSL Browser Fix: Open links in Windows browser
if vim.fn.has("wsl") == 1 then
  vim.g.browse_command = "powershell.exe -NoProfile -Command Start-Process"
  -- Also for snacks and other plugins that use vim.ui.open
  if vim.fn.has("nvim-0.10") == 1 then
    vim.ui.open = function(path)
      vim.fn.jobstart({ "powershell.exe", "-NoProfile", "-Command", "Start-Process", '"' .. path .. '"' })
    end
  end
end

-- UI
opt.number = true                  -- Show line numbers
opt.relativenumber = true          -- Relative line numbers
opt.cursorline = true             -- Highlight current line
opt.signcolumn = "yes"            -- Always show sign column
opt.termguicolors = true          -- True color support
opt.scrolloff = 8                 -- Keep 8 lines above/below cursor
opt.sidescrolloff = 8
opt.showmode = false              -- Don't show mode (lualine shows it)
opt.cmdheight = 1                 -- Command line height (1 line)
opt.showcmd = true                -- Show partial commands in status line
opt.laststatus = 3                -- Global statusline (helps with cmdline)
opt.fillchars = { eob = " " }     -- Hide ~ at the end of buffer

-- Indentation
opt.expandtab = true              -- Use spaces instead of tabs
opt.shiftwidth = 2                -- Indent width
opt.tabstop = 2                   -- Tab width
opt.softtabstop = 2
opt.smartindent = true            -- Smart autoindenting
opt.breakindent = true            -- Wrap indent to match line start

-- Search
opt.ignorecase = true             -- Ignore case in search
opt.smartcase = true              -- Unless uppercase is used
opt.hlsearch = true               -- Highlight search results
opt.incsearch = true              -- Incremental search

-- Performance
opt.updatetime = 250
opt.timeoutlen = 300
opt.lazyredraw = false
opt.splitbelow = true             -- Horizontal splits go below
opt.splitright = true             -- Vertical splits go right

-- Backup
opt.backup = false
opt.writebackup = false
opt.undofile = true               -- Persistent undo
-- Bound retained edit history; bulk replacements can otherwise keep thousands
-- of copies of changed text alive. Persistent undo remains enabled.
opt.undolevels = 1000

-- Folding (manual by default for max typing speed; enable treesitter folds on demand)
opt.foldmethod = "manual"
opt.foldenable = false            -- Don't fold by default
opt.foldlevel = 99                -- High fold level to keep most folds open

-- Fix command-line display (redraw after commands)
vim.api.nvim_create_autocmd("CmdlineLeave", {
  callback = function()
    vim.defer_fn(function()
      vim.cmd("redraw")
    end, 100)
  end,
})

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ higroup = "Visual", timeout = 200 })
  end,
})

-- Auto-create directories when saving files
vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- Close certain filetypes with 'q'
vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "qf",
    "help",
    "man",
    "notify",
    "lspinfo",
    "spectre_panel",
    "startuptime",
    "tsplayground",
    "PlenaryTestPopup",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
})
