-- nvim-treesitter `main` branch (rewrite). The old `master` API
-- (nvim-treesitter.configs, module setup tables) is gone: highlighting is
-- started per-buffer with vim.treesitter.start(), and parser install is an
-- explicit call. Textobjects (also `main`) exposes plain functions we bind
-- ourselves instead of a keymaps table.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    lazy = true,
    config = function()
      local parsers = {
        "bash", "c", "cpp", "css", "go", "html", "javascript", "json",
        "lua", "markdown", "markdown_inline", "python", "rust",
        "typescript", "vim", "vimdoc", "yaml"
      }

      -- Compile any missing parsers into stdpath('data')/site (async, no-op
      -- when already installed). Don't auto-install on the fly: mid-edit
      -- compiles caused hitches; add new languages to `parsers` above instead.
      require("nvim-treesitter").install(parsers)

      -- Enable highlight + indent + folds per buffer once its parser exists.
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true }),
        callback = function(ev)
          local lang = vim.treesitter.language.get_lang(ev.match)
          if not lang or not pcall(vim.treesitter.start, ev.buf, lang) then
            return -- no parser for this filetype; keep regex highlighting
          end
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          -- Treesitter folds disabled: foldmethod=expr recomputes all folds on every
          -- file open. settings.lua keeps foldmethod=manual + foldenable=false; use
          -- :set foldmethod=expr manually when you need folds on a specific buffer.
        end,
      })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
        },
        move = {
          set_jumps = true,
        },
      })

      local select = function(query)
        return function()
          require("nvim-treesitter-textobjects.select").select_textobject(query, "textobjects")
        end
      end
      local move = function(fn, query)
        return function()
          require("nvim-treesitter-textobjects.move")[fn](query, "textobjects")
        end
      end

      -- Select (same captures as the old keymaps table)
      vim.keymap.set({ "x", "o" }, "af", select("@function.outer"))
      vim.keymap.set({ "x", "o" }, "if", select("@function.inner"))
      vim.keymap.set({ "x", "o" }, "ac", select("@class.outer"))
      vim.keymap.set({ "x", "o" }, "ic", select("@class.inner"))
      vim.keymap.set({ "x", "o" }, "ai", select("@conditional.outer"))
      vim.keymap.set({ "x", "o" }, "ii", select("@conditional.inner"))
      vim.keymap.set({ "x", "o" }, "al", select("@loop.outer"))
      vim.keymap.set({ "x", "o" }, "il", select("@loop.inner"))

      -- Move (matches [q/]q quickfix bracket-pair style in keymaps.lua)
      vim.keymap.set({ "n", "x", "o" }, "]f", move("goto_next_start", "@function.outer"))
      vim.keymap.set({ "n", "x", "o" }, "]c", move("goto_next_start", "@class.outer"))
      vim.keymap.set({ "n", "x", "o" }, "]F", move("goto_next_end", "@function.outer"))
      vim.keymap.set({ "n", "x", "o" }, "]C", move("goto_next_end", "@class.outer"))
      vim.keymap.set({ "n", "x", "o" }, "[f", move("goto_previous_start", "@function.outer"))
      vim.keymap.set({ "n", "x", "o" }, "[c", move("goto_previous_start", "@class.outer"))
      vim.keymap.set({ "n", "x", "o" }, "[F", move("goto_previous_end", "@function.outer"))
      vim.keymap.set({ "n", "x", "o" }, "[C", move("goto_previous_end", "@class.outer"))
    end,
  },
}
