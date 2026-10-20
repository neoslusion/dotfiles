-- LSP Configuration - Language Server Protocol
-- Provides code intelligence, diagnostics, and navigation
-- Updated for Neovim 0.11+ using vim.lsp.config API
return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPost", "BufNewFile" },
  lazy = true,
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp",
    {
      "folke/lazydev.nvim",
      ft = "lua",
      opts = {
        library = {
          { path = "luvit-meta/library", words = { "vim%.uv" } },
        },
      },
    },
    { "Bilal2453/luvit-meta", lazy = true },
  },
  config = function()
    local cmp_nvim_lsp = require("cmp_nvim_lsp")

    -- Enable completion capabilities
    local capabilities = cmp_nvim_lsp.default_capabilities()

    -- Native configuration uses lspconfig's data without its deprecated setup
    -- framework or a global deprecation-warning override.
    local servers = {}
    local function setup_lsp(name, config)
      config = config or {}
      config.capabilities = capabilities
      vim.lsp.config(name, config)
      servers[#servers + 1] = name
    end

    -- Configure individual language servers

    -- Lua Language Server (for Neovim configuration)
    setup_lsp("lua_ls", {})

    -- Python Language Server
    setup_lsp("pyright", {})

    -- JavaScript/TypeScript Language Server
    setup_lsp("ts_ls", {})

    -- Bash Language Server
    setup_lsp("bashls", {})

    -- JSON Language Server
    setup_lsp("jsonls", {})

    -- YAML Language Server
    setup_lsp("yamlls", {})

    -- C/C++ Language Server
    setup_lsp("clangd", {
      -- Auto-detect compile_commands.json in common out-of-tree build dirs.
      -- clangd only searches the source file's ancestors, so a database in
      -- e.g. Build/ (sibling of the sources) is invisible without this.
      cmd = function(dispatchers, config)
        local cmd = {
          vim.fn.exepath("clangd"),
          "--background-index",
          "--background-index-priority=low",
          -- Neovim records even informational stderr tracing as ERROR.
          "--log=error",
          "--clang-tidy",
          "--header-insertion=iwyu",
          "--completion-style=detailed",
          "--function-arg-placeholders",
          "--fallback-style=llvm",
          -- Anchor host/cross-driver queries to bin paths: bare *gcc* is too
          -- broad. ** spans native Windows and WSL mount forms.
          "--query-driver=/usr/bin/*gcc*,/usr/bin/clang*,**/bin/*-gcc*,**/bin/*gcc*,**/bin/clang*,**/tricore-gcc*",
        }
        if vim.fn.has("win32") == 1 then cmd[#cmd + 1] = "-j=2" end
        local candidates = {
          "Build", "build", "out/build",
          "cmake-build-debug", "cmake-build-release",
        }
        for _, dir in ipairs(candidates) do
          local db = config.root_dir and (config.root_dir .. "/" .. dir)
          if db and vim.uv.fs_stat(db .. "/compile_commands.json") then
            cmd[#cmd + 1] = "--compile-commands-dir=" .. db
            break
          end
        end
        return vim.lsp.rpc.start(cmd, dispatchers, {
          cwd = config.cmd_cwd,
          env = config.cmd_env,
          detached = config.detached,
        })
      end,
      init_options = {
        usePlaceholders = true,
        completeUnimported = true,
        clangdFileStatus = true,
      },
    })

    -- Rust Language Server
    setup_lsp("rust_analyzer", {
      settings = {
        ["rust-analyzer"] = {
          checkOnSave = {
            command = "clippy",
          },
        },
      },
    })

    -- Enabling inside BufReadPost replays FileType while detection is still
    -- running. Activate the batch after that event so filetypes stay intact.
    vim.schedule(function() vim.lsp.enable(servers) end)

    -- Diagnostic configuration
    vim.diagnostic.config({
      virtual_text = true,
      signs = {
        text = {
          [vim.diagnostic.severity.ERROR] = " ",
          [vim.diagnostic.severity.WARN] = " ",
          [vim.diagnostic.severity.HINT] = " ",
          [vim.diagnostic.severity.INFO] = " ",
        },
      },
      update_in_insert = false,
      underline = true,
      severity_sort = true,
      float = {
        border = "rounded",
        source = true,
      },
    })

    -- LSP Keybindings (set when LSP attaches to buffer)
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", {}),
      callback = function(args)
        local opts = { buffer = args.buf, silent = true }

        -- Navigation
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
        vim.keymap.set("n", "<F12>", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "Go to implementation" }))
        vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "Show references" }))
        vim.keymap.set("n", "<S-F12>", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "Show references" }))

        -- Information
        vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
        vim.keymap.set("n", "<leader>k", vim.lsp.buf.signature_help, vim.tbl_extend("force", opts, { desc = "Signature help" }))

        -- Code actions
        vim.keymap.set("n", "<leader>rn", ":IncRename ", vim.tbl_extend("force", opts, { desc = "Rename symbol" }))
        vim.keymap.set("n", "<F2>", ":IncRename ", vim.tbl_extend("force", opts, { desc = "Rename symbol" }))
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code action" }))
        -- Note: <C-.> removed -- terminals rarely deliver Ctrl+punctuation; use <leader>ca.
        
        -- Formatting is handled by conform.nvim (see keymaps.lua and extras.lua)

        -- Diagnostics
        vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, vim.tbl_extend("force", opts, { desc = "Previous diagnostic" }))
        vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))
        vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, vim.tbl_extend("force", opts, { desc = "Show diagnostic" }))
        vim.keymap.set("n", "<leader>dl", vim.diagnostic.setloclist, vim.tbl_extend("force", opts, { desc = "Diagnostic list" }))

        -- Workspace
        vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, vim.tbl_extend("force", opts, { desc = "Add workspace folder" }))
        vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, vim.tbl_extend("force", opts, { desc = "Remove workspace folder" }))
        vim.keymap.set("n", "<leader>wL", function()
          print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, vim.tbl_extend("force", opts, { desc = "List workspace folders" }))
      end,
    })
  end,
}
