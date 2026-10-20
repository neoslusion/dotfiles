return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    -- Dual-bind: Alt+Arrows and Alt+HJKL for cross-muxer navigation parity
    { "<m-Left>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate Left (Alt+Arrow)" },
    { "<m-Down>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate Down (Alt+Arrow)" },
    { "<m-Up>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate Up (Alt+Arrow)" },
    { "<m-Right>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate Right (Alt+Arrow)" },
    { "<m-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate Left (Alt+H)" },
    { "<m-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate Down (Alt+J)" },
    { "<m-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate Up (Alt+K)" },
    { "<m-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate Right (Alt+L)" },
  },
}

