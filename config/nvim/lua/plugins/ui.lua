return {
  -- Bufferline (Tabs)
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>bP", "<Cmd>BufferLineTogglePin<CR>", desc = "Toggle Pin" },
      { "<leader>bN", "<Cmd>BufferLineGroupClose ungrouped<CR>", desc = "Delete Non-Pinned Buffers" },
      { "<leader>bo", "<Cmd>BufferLineCloseOthers<CR>", desc = "Delete Other Buffers" },
      { "<leader>br", "<Cmd>BufferLineCloseRight<CR>", desc = "Delete Buffers to the Right" },
      { "<leader>bl", "<Cmd>BufferLineCloseLeft<CR>", desc = "Delete Buffers to the Left" },
      { "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
      { "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
      { "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
      { "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
    },
    opts = {
      options = {
        close_command = function(n)
          Snacks.bufdelete(n)
        end,
        right_mouse_command = function(n)
          Snacks.bufdelete(n)
        end,
        diagnostics = false, -- Diagnostics remain in the gutter and statusline
        show_buffer_icons = false,
        show_buffer_close_icons = false,
        show_close_icon = false,
        separator_style = "thin",
        always_show_bufferline = false,
        -- Hide the dashboard buffer from the tabline
        custom_filter = function(buf_number)
          if vim.bo[buf_number].filetype == "snacks_dashboard" then
            return false
          end
          -- Hide empty [No Name] buffers
          if vim.fn.bufname(buf_number) == "" and vim.bo[buf_number].buftype == "" then
            return false
          end
          return true
        end,
        offsets = {
          {
            filetype = "neo-tree",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "left",
          },
        },
      },
    },
    config = function(_, opts)
      require("bufferline").setup(opts)
    end,
  },

  -- Lualine (Status Line)
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    init = function()
      vim.g.lualine_laststatus = vim.o.laststatus
      if vim.fn.argc(-1) > 0 then
        -- set an empty statusline till lualine loads
        vim.o.statusline = " "
      else
        -- hide the statusline on the starter page
        vim.o.laststatus = 0
      end
    end,
    opts = function()
      local lualine_require = require("lualine_require")
      lualine_require.require = require

      local icons = {
        diagnostics = {
          Error = "E:",
          Warn = "W:",
          Hint = "H:",
          Info = "I:",
        },
        git = {
          added = "+",
          modified = "~",
          removed = "-",
        },
      }

      vim.o.laststatus = vim.g.lualine_laststatus

      return {
        options = {
          theme = "tokyonight",
          icons_enabled = false,
          globalstatus = true,
          refresh = { refresh_time = 50 },
          disabled_filetypes = { statusline = { "dashboard", "alpha", "starter" } },
          component_separators = "",
          section_separators = "",
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch" },
          lualine_c = {
            {
              "diagnostics",
              symbols = {
                error = icons.diagnostics.Error,
                warn = icons.diagnostics.Warn,
                info = icons.diagnostics.Info,
                hint = icons.diagnostics.Hint,
              },
            },
            "filetype",
            { "filename", path = 1 },
          },
          lualine_x = {
            {
              "diff",
              -- Gitsigns already computes buffer changes. Reuse those counts
              -- instead of starting another git diff on buffer switches/saves.
              source = function()
                local status = vim.b.gitsigns_status_dict
                if status then
                  return { added = status.added, modified = status.changed, removed = status.removed }
                end
              end,
              symbols = {
                added = icons.git.added,
                modified = icons.git.modified,
                removed = icons.git.removed,
              },
            },
          },
          lualine_y = {
            { "progress", separator = " ", padding = { left = 1, right = 0 } },
            { "location", padding = { left = 0, right = 1 } },
          },
          lualine_z = {},
        },
        extensions = { "neo-tree", "lazy" },
      }
    end,
  },

  -- Neo-tree (File Explorer)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      {
        "<leader>e",
        "<cmd>Neotree toggle<cr>",
        desc = "Toggle NeoTree",
      },
      {
        "<leader>E",
        "<cmd>Neotree reveal<cr>",
        desc = "Reveal in NeoTree",
      },
      -- Note: <C-b> is NOT bound here -- tmux's default prefix is C-b and swallows it
      -- before Neovim sees it. Use <leader>e to toggle the tree instead.
    },
    deactivate = function()
      vim.cmd([[Neotree close]])
    end,
    opts = {
      sources = { "filesystem", "buffers", "git_status", "document_symbols" },
      open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "Outline" },
      filesystem = {
        bind_to_cwd = false,
        follow_current_file = { enabled = true },
        -- Windows watcher handles retain callbacks after stop, and busy build
        -- trees can flood the event queue. Neo-tree refreshes on writes instead;
        -- use R for changes made outside the editor.
        use_libuv_file_watcher = vim.fn.has("win32") == 0,
      },
      window = {
        position = "left",
        width = 30,
        mappings = {
          ["<space>"] = "none",
          ["l"] = "open",
          ["h"] = "close_node",
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true, -- if nil and file nesting is enabled, will enable expanders
          expander_collapsed = "",
          expander_expanded = "",
          expander_highlight = "NeoTreeExpander",
        },
        git_status = {
          symbols = {
            added = "", -- or "✚", but this is redundant info if you use git_status_colors on the name
            modified = "", -- or "", but this is redundant info if you use git_status_colors on the name
            deleted = "", -- this can only be used in the git_status source
            renamed = "", -- this can only be used in the git_status source
            -- Status type
            untracked = "",
            ignored = "",
            unstaged = "",
            staged = "",
            conflict = "",
          },
        },
      },
    },
    config = function(_, opts)
      require("neo-tree").setup(opts)
    end,
  },

  -- Smooth movement is provided by smear-cursor (cursor) + snacks.scroll (scroll).
  -- mini.animate was removed: its cursor animation duplicated smear-cursor.

  -- Icons
  { "nvim-tree/nvim-web-devicons", lazy = true },
  { "echasnovski/mini.icons", version = false },
}
