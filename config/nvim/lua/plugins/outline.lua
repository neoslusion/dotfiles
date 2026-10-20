-- Symbol Outline (VS Code Outline view)
return {
  "stevearc/aerial.nvim",
  -- Don't collect document symbols in the background until the outline is used.
  cmd = {
    "AerialToggle", "AerialOpen", "AerialOpenAll", "AerialClose", "AerialCloseAll",
    "AerialNext", "AerialPrev", "AerialGo", "AerialInfo",
    "AerialNavToggle", "AerialNavOpen", "AerialNavClose",
  },
  opts = {
    attach_mode = "global",
    backends = { "lsp", "treesitter", "markdown", "man" },
    show_guides = true,
    layout = {
      resize_to_content = false,
      win_opts = {
        winblend = 0,
      },
    },
    -- Use specific icons if you want
    guides = {
      mid_item = "├╴",
      last_item = "└╴",
      nested_top = "│ ",
      whitespace = "  ",
    },
  },
  keys = {
    { "<leader>o", "<cmd>AerialToggle<cr>", desc = "Outline" },
  },
}
