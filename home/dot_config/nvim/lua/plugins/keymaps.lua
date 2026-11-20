local keymap = vim.keymap

local map = function(keymaps)
	for _, keymap_entry in ipairs(keymaps) do
		local lhs = keymap_entry[1]
		local rhs = keymap_entry[2]
		local mode = keymap_entry.mode or "n"
		local opts = {
			desc = keymap_entry.desc,
			silent = keymap_entry.silent ~= false,
			noremap = keymap_entry.noremap ~= false,
			expr = keymap_entry.expr,
			nowait = keymap_entry.nowait,
			buffer = keymap_entry.buffer,
		}
		keymap.set(mode, lhs, rhs, opts)
	end
end

-- Oil - File explorer
map({
	{
		"sf",
		function()
			require("oil").open_float(nil, { preview = {} })
		end,
		desc = "Toggle file explorer",
	},
})

-- LSP
local Snacks = require("snacks")
map({
	-- { "gd", vim.lsp.buf.definition, desc = "Goto Definition" },
	-- {
	-- 	"gr",
	-- 	vim.lsp.buf.references,
	-- 	desc = "References",
	-- 	nowait = true,
	-- },
	{ "gI", vim.lsp.buf.implementation, desc = "Goto Implementation" },
	-- { "gy", vim.lsp.buf.type_definition, desc = "Goto T[y]pe Definition" },
	-- { "gD", vim.lsp.buf.declaration, desc = "Goto Declaration" },
	{
		"gd",
		function()
			Snacks.picker.lsp_definitions({ jump = { reuse_win = false } })
		end,
		desc = "LSP Goto Definition",
	},
	{ "gD", Snacks.picker.lsp_declarations, desc = "LSP Goto Declaration" },
	{ "gy", Snacks.picker.lsp_type_definitions, desc = "LSP Goto T[y]pe Definition" },
	{ "gr", Snacks.picker.lsp_references, desc = "LSP Goto Definition" },
	{ "K", vim.lsp.buf.hover, desc = "Hover" },
	{ "gK", vim.lsp.buf.signature_help, desc = "Signature Help" },
	{
		"<c-k>",
		vim.lsp.buf.signature_help,
		desc = "Signature Help",
		mode = "i",
	},
	{
		"<c-j>",
		function()
			vim.diagnostic.jump({ count = 1, float = true })
		end,
		desc = "Jump to next diagnostic",
		mode = "n",
	},
	{
		"<leader>ca",
		vim.lsp.buf.code_action,
		desc = "Code Action",
		mode = { "n", "x" },
	},
	{ "<leader>cr", vim.lsp.buf.rename, desc = "Rename" },
	{
		"<leader>f",
		function()
			require("conform").format()
		end,
		desc = "Format code",
		mode = { "n", "x" },
	},
})

-- Snacks
map({
	{ "<leader>cl", Snacks.picker.lsp_config, desc = "Lsp Info" },
	{ "<leader>cR", Snacks.rename.rename_file, desc = "Rename File" },
	{ ";f", Snacks.picker.files, desc = "Find files" },
	{ ";r", Snacks.picker.grep, desc = "Live grep" },
	{ ";;", Snacks.picker.resume, desc = "Resume picker" },
	{
		"\\\\",
		function()
			Snacks.picker.buffers({
				confirm = function(picker, item)
					picker:close()
					if not item then
						return
					end
					-- If the buffer is already shown in a window (any tab),
					-- jump to that window instead of opening it here.
					vim.schedule(function()
						for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
							for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
								if vim.api.nvim_win_get_buf(win) == item.buf then
									vim.api.nvim_set_current_tabpage(tab)
									vim.api.nvim_set_current_win(win)
									return
								end
							end
						end
						vim.api.nvim_set_current_buf(item.buf)
					end)
				end,
			})
		end,
		desc = "List buffers",
	},
	{ ";e", Snacks.picker.diagnostics, desc = "Diagnostics" },
	{ ";c", Snacks.picker.lsp_incoming_calls, desc = "LSP incoming calls" },
	{ ";n", Snacks.picker.notifications, desc = "Notifications" },
	{
		";g",
		function()
			Snacks.lazygit()
		end,
		desc = "Lazygit",
	},
	{
		";h",
		Snacks.picker.git_diff,
		desc = "Git Diff (Hunks)",
	},
	{
		"]]",
		function()
			Snacks.words.jump(vim.v.count1)
		end,
		desc = "Next Reference",
		mode = { "n", "t" },
	},
	{
		"[[",
		function()
			Snacks.words.jump(-vim.v.count1)
		end,
		desc = "Prev Reference",
		mode = { "n", "t" },
	},
})

-- Gitsigns
map({
	{
		"<leader>gb",
		function()
			require("gitsigns").blame_line()
		end,
		desc = "Blame current line",
	},
	{
		"<leader>gB",
		function()
			require("gitsigns").blame()
		end,
		desc = "Blame buffer",
	},
	{
		"<leader>go",
		function()
			local async = require("gitsigns.async")
			local cache = require("gitsigns.cache").cache

			async.run(function()
				local bufnr = vim.api.nvim_get_current_buf()
				local lnum = vim.api.nvim_win_get_cursor(0)[1]
				local bcache = cache[bufnr]
				if not bcache then
					return
				end

				bcache:get_blame(lnum)
				local blame = bcache.blame
				if not blame or not blame.entries or not blame.entries[lnum] then
					return
				end

				local info = blame.entries[lnum]
				local sha = info.commit.sha

				-- Check if uncommitted (sha is all zeros)
				if tonumber("0x" .. sha:sub(1, 8)) == 0 then
					vim.notify("Line not committed yet", vim.log.levels.WARN)
					return
				end

				vim.cmd.tabnew()
				require("gitsigns.actions.diffthis").show(bufnr, sha, info.filename)
				async.schedule()
				pcall(vim.api.nvim_win_set_cursor, 0, { info.orig_lnum or lnum, 0 })
			end)
		end,
		desc = "Open file from blamed commit",
	},
	{
		"<leader>gs",
		function()
			local gs = require("gitsigns")
			if #(gs.get_hunks() or {}) > 0 then
				gs.stage_buffer()
			else
				gs.reset_buffer_index()
			end
		end,
		desc = "Toggle stage buffer",
	},
	{
		"<leader>gh",
		function()
			require("gitsigns").stage_hunk()
		end,
		desc = "Toggle stage hunk",
	},
})

-- MiniDiff
map({
	{
		"<leader>gd",
		function()
			local MiniDiff = require("mini.diff")
			MiniDiff.toggle_overlay()
		end,
		desc = "Toggle MiniDiff overlay",
	},
})

-- CodeDiff
map({
	{ "<leader>dv", "<cmd>CodeDiff<cr>", desc = "Toggle CodeDiff" },
	-- File history
	{ "<leader>dh", "<cmd>CodeDiff history %<cr>", desc = "File history (current file)" },
	{ "<leader>dH", "<cmd>CodeDiff history<cr>", desc = "File history (repo)" },
})

-- Harpoon
map({
	{ "<leader>a", function() require("harpoon"):list():add() end, desc = "Add file to Harpoon" },
	{ "<leader>h", function() local h = require("harpoon"); h.ui:toggle_quick_menu(h:list()) end, desc = "Harpoon quick menu" },
	{ "<leader>1", function() require("harpoon"):list():select(1) end, desc = "Harpoon file 1" },
	{ "<leader>2", function() require("harpoon"):list():select(2) end, desc = "Harpoon file 2" },
	{ "<leader>3", function() require("harpoon"):list():select(3) end, desc = "Harpoon file 3" },
	{ "<leader>4", function() require("harpoon"):list():select(4) end, desc = "Harpoon file 4" },
	{ "<leader>5", function() require("harpoon"):list():select(5) end, desc = "Harpoon file 5" },
})

-- Tmux navigator
map({
	{ "<M-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate left (tmux)" },
	{ "<M-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate down (tmux)" },
	{ "<M-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate up (tmux)" },
	{ "<M-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (tmux)" },
	{ "<M-Left>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate left (tmux)" },
	{ "<M-Down>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate down (tmux)" },
	{ "<M-Up>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate up (tmux)" },
	{ "<M-Right>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (tmux)" },
})
