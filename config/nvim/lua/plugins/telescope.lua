-- Telescope: Fuzzy finder
return {
  "nvim-telescope/telescope.nvim",
  cmd = "Telescope",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  keys = {
    { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
    { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
    { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
    { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
    { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent Files" },
    { "<leader>fc", "<cmd>Telescope commands<cr>", desc = "Commands" },
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    telescope.setup({
      defaults = {
        -- Large generated files remain selectable without reading them into previews.
        preview = { filesize_limit = 1 },
        prompt_prefix = "> ",
        selection_caret = "> ",
        path_display = { "smart" },
        mappings = {
          i = {
            ["<C-j>"] = actions.move_selection_next,
            ["<C-k>"] = actions.move_selection_previous,
            ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
          },
        },
      },
      pickers = {
        find_files = {
          hidden = true,
          find_command = {
            "rg",
            "--files",
            "--hidden",
            "--glob",
            "!.git/*",
            "--glob",
            "!node_modules/*",
            "--glob",
            "!.next/*",
            "--glob",
            "!dist/*",
            "--glob",
            "!target/*",
            "--glob",
            "!.venv/*",
            "--glob",
            "!build/*",
          },
        },
      },
    })

    telescope.load_extension("fzf")
  end,
}
