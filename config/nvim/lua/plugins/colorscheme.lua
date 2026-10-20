-- Colorscheme: Tokyo Night
return {
  "folke/tokyonight.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    ---@diagnostic disable-next-line: missing-fields
    require("tokyonight").setup({
      style = "night",
      transparent = true,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
      },
    })
    vim.cmd([[colorscheme tokyonight]])
  end,
}
