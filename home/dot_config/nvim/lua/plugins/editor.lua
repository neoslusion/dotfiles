-- Completion
-- Set up on the first insert or command line, not at startup: setup spawns two
-- git processes to check its prebuilt binary, and on Windows spawning them
-- blocks the UI for ~350 ms.
vim.api.nvim_create_autocmd({ "InsertEnter", "CmdlineEnter" }, {
	once = true,
	callback = function()
		require("blink.cmp").setup({
			snippets = {
				preset = "default",
			},
			completion = {
				accept = {
					-- experimental auto-brackets support
					auto_brackets = {
						enabled = true,
					},
				},
				menu = {
					border = "none",
					draw = {
						treesitter = { "lsp" },
					},
				},
				documentation = {
					auto_show = true,
					auto_show_delay_ms = 200,
				},
			},

			-- sources = {
			--   -- adding any nvim-cmp sources here will enable them
			--   -- with blink.compat
			--   compat = {},
			--   default = { "lsp", "path", "snippets", "buffer" },
			-- },

			cmdline = {
				enabled = true,
				keymap = {
					preset = "cmdline",
					["<Right>"] = false,
					["<Left>"] = false,
				},
				completion = {
					list = { selection = { preselect = false } },
					menu = {
						auto_show = function(ctx)
							return vim.fn.getcmdtype() == ":"
						end,
					},
					ghost_text = { enabled = true },
				},
			},

			keymap = {
				preset = "enter",
				["c-y"] = { "select_and_accept" },
			},

			appearance = {
				kind_icons = Util.icons.kinds,
			},
		})
	end,
})

require("mini.pairs").setup({
	modes = { insert = true, command = true, terminal = false },
})

require("mini.diff").setup({
	view = {
		-- show whole reference part above whole buffer part, as in `git diff`
		overlay_style = "hunk",
	},
	mappings = {
		-- same keymaps as codediff.nvim
		goto_next = "]c",
		goto_prev = "[c",
	},
})
-- Comments
require("todo-comments").setup()

-- Git integration
require("gitsigns").setup()
require("gitlinker").setup()

-- Formatting
require("conform").setup({
	default_format_opts = {
		timeout_ms = 3000,
		async = false,
		quiet = false,
		lsp_format = "fallback",
	},
	formatters_by_ft = {
		lua = { "stylua" },
		sh = { "shfmt" },
		bash = { "shfmt" },
	},
	format_on_save = function(bufnr)
		if vim.b[bufnr].disable_autoformat then
			return
		end
		return { timeout_ms = 500, lsp_format = "never" }
	end,
})

-- Colors
vim.lsp.document_color.enable(false)
require("nvim-highlight-colors").setup({
	render = "background",
	enable_hex = true,
	enable_short_hex = true,
	enable_rgb = true,
	enable_hsl = true,
	enable_hsl_without_function = true,
	enable_ansi = true,
	enable_var_usage = true,
	enable_tailwind = false,
})
