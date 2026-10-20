-- Autocompletion
return {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-nvim-lsp",
    "L3MON4D3/LuaSnip",
    "saadparwaiz1/cmp_luasnip",
    "rafamadriz/friendly-snippets",
  },
  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")
    local default_enabled = cmp.get_config().enabled

    require("luasnip.loaders.from_vscode").lazy_load()

    cmp.setup({
      performance = { max_view_entries = 40 },
      window = { completion = { max_height = 10 } },
      -- Snacks marks big files with this flag; cmp does not honor it itself.
      -- Preserve cmp's prompt/macro checks while avoiding whole-buffer scans.
      enabled = function()
        return vim.b.completion ~= false and default_enabled()
      end,
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        -- Explicit even though preset.insert implies both: these own
        -- insert-mode <C-n>/<C-p> (menu nav). keymaps.lua must not claim
        -- them in insert mode -- buffer-local cmp maps beat global ones
        -- after InsertEnter, which previously killed those claims silently.
        ["<C-n>"] = cmp.mapping.select_next_item(),
        ["<C-p>"] = cmp.mapping.select_prev_item(),
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-j>"] = cmp.mapping.select_next_item(),
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({ select = true }),
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
          elseif luasnip.expand_or_jumpable() then
            luasnip.expand_or_jump()
          else
            fallback()
          end
        end, { "i", "s" }),
        ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
      }),
      sources = {
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "path" },
      },
      formatting = {
        fields = { "abbr", "kind", "menu" },
        format = function(entry, item)
          -- Professional text-only formatting (no icons)
          item.kind = string.format("[%s]", item.kind)
          item.menu = ({
            nvim_lsp = "[LSP]",
            luasnip = "[Snippet]",
            buffer = "[Buffer]",
            path = "[Path]",
          })[entry.source.name]
          return item
        end,
      },
    })
  end,
}
