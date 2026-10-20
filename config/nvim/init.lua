-- nvim: personal neovim configuration
-- Bootstrap lazy.nvim plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)
vim.loader.enable()

-- Keep plugin loading and configuration below as the only mandatory startup
-- work. The lazy.nvim setup owns colorscheme and event-driven plugins.
require("config.settings")
require("config.keymaps")

require("lazy").setup("plugins", {
  defaults = {
    lazy = true,
  },
  install = {
    colorscheme = { "tokyonight" },
  },
  checker = {
    enabled = false,
    notify = false,
  },
  change_detection = {
    notify = false,
  },
})
