return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    -- Big features
    bigfile = {
      enabled = true,
      setup = function(ctx)
        if vim.fn.exists(":NoMatchParen") ~= 0 then
          vim.cmd("NoMatchParen")
        end
        Snacks.util.wo(0, { foldmethod = "manual", statuscolumn = "", conceallevel = 0 })
        vim.b[ctx.buf].completion = false
        vim.b[ctx.buf].snacks_indent = false
        -- The default bigfile setup restores regex syntax after detection.
        -- Keep huge logs/generated files cheap and bound whole-file undo edits.
        vim.bo[ctx.buf].syntax = ""
        vim.bo[ctx.buf].undolevels = 100
      end,
    },
    dashboard = { enabled = false },
    explorer = { enabled = false }, -- We keep neo-tree for now
    indent = { enabled = false },
    input = { enabled = true }, -- Replaces dressed.nvim / standard input
    notifier = { enabled = true, style = "minimal" },
    quickfile = { enabled = false }, -- Disabled to prevent rapid visual flash on file open
    scroll = { enabled = false }, -- Disabled: per-scroll easing adds overhead on Windows
    statuscolumn = { enabled = false }, -- Native sign column keeps Git/LSP signs
    words = { enabled = false }, -- Disabled: fires on every CursorHold (250ms), costly on large files
    
    -- Utilities
    bufdelete = { enabled = true }, -- Replaces bufdelete
    gitbrowse = { enabled = true }, -- Open remote git repo
    lazygit = { enabled = true }, -- Replaces lazygit.nvim
    terminal = { enabled = true }, -- Replaces toggleterm
    toggle = { enabled = true },
  },
  keys = {
    -- Top Pickers & Explorer
    { "<leader><space>", function() Snacks.picker.smart() end, desc = "Smart Find Files" },
    { "<leader>,", function() Snacks.picker.buffers() end, desc = "Buffers" },
    -- Grep lives under the search group: <leader>/ is literal in-buffer search
    -- (config/keymaps.lua) and must not collide with it.
    { "<leader>sg", function() Snacks.picker.grep() end, desc = "Grep" },
    { "<leader>:", function() Snacks.picker.command_history() end, desc = "Command History" },
    { "<leader>un", function() Snacks.picker.notifications() end, desc = "Notification History" },
    
    -- Git
    { "<leader>gg", function() Snacks.lazygit() end, desc = "Lazygit" },
    { "<M-g>", function() Snacks.lazygit() end, desc = "Lazygit (Alt+g)" },
    { "<leader>gb", function() Snacks.git.blame_line() end, desc = "Git Blame Line" },
    { "<leader>gB", function() Snacks.gitbrowse() end, desc = "Git Browse" },
    
    -- Utils
    { "<leader>bd", function() Snacks.bufdelete() end, desc = "Delete Buffer" },
    { "<leader>cR", function() Snacks.rename.rename_file() end, desc = "Rename File" },
    { "<leader>ft", function() Snacks.terminal() end, desc = "Toggle Terminal" },
    
    -- Words (Illumination)
    { "]]", function() Snacks.words.jump(1, true) end, desc = "Next Reference" },
    { "[[", function() Snacks.words.jump(-1, true) end, desc = "Prev Reference" },
  },
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        -- Setup some globals for debugging (optional)
        ---@diagnostic disable-next-line: duplicate-set-field
        _G.dd = function(...)
          Snacks.debug.inspect(...)
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        _G.bt = function()
          Snacks.debug.backtrace()
        end
        vim.print = _G.dd -- Override print to use snacks for nicer output
      end,
    })
  end,
}
