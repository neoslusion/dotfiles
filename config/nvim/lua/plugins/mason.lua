-- Mason - LSP, DAP, Linter, and Formatter Package Manager
-- Automatically installs and manages language servers
return {
  "williamboman/mason.nvim",
  dependencies = {
    "williamboman/mason-lspconfig.nvim",
  },
  config = function()
    -- Setup mason
    require("mason").setup({
      ui = {
        border = "rounded",
        icons = {
          package_installed = "[I]",
          package_pending = "[P]",
          package_uninstalled = "[U]",
        },
      },
    })

    -- Prebuilt-binary servers install on any machine; the npm-based ones need
    -- node/npm on PATH. In WSL that's the nvm default exposed non-lazily (see
    -- core.zsh); on Windows it needs a system Node install. Only request the npm
    -- group when npm is actually on PATH, so Mason never errors on a machine that
    -- can't build them — and they start installing automatically once npm shows up.
    local servers = { "lua_ls", "clangd", "rust_analyzer" }
    if vim.fn.executable("npm") == 1 then
      vim.list_extend(servers, { "pyright", "ts_ls", "bashls", "jsonls", "yamlls" })
    end

    require("mason-lspconfig").setup({
      ensure_installed = servers,
      -- Don't check/install on every file open (adds disk/network to the open
      -- path). `ensure_installed` installs once; run `:Mason` to add more.
      automatic_installation = false,
      -- The native setup in lsp.lua owns enabled servers and their flags;
      -- don't start installed servers with stock configs before that setup.
      automatic_enable = false,
    })
  end,
}
