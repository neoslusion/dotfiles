return {
  "akinsho/git-conflict.nvim",
  version = "*",
  config = function()
    ---@diagnostic disable-next-line: missing-fields
    require("git-conflict").setup({
      default_mappings = true, -- gives you co (choose ours), ct (choose theirs), cb (choose both), c0 (choose none), ]x (next), [x (prev)
      list_opener = "copen", -- command or function to open the list of conflicts
      highlights = {
        incoming = "DiffAdd",
        current = "DiffText",
      },
    })
  end,
}
