local TS = require("nvim-treesitter")

-- Leave CC alone: `tree-sitter build` finds a compiler itself (zig/MSVC on
-- Windows). Forcing CC=gcc broke parser builds on machines without gcc.

local ensure_installed = {
	"bash",
	"c",
	"cmake",
	"cpp",
	"diff",
	"gitignore",
	"go",
	"json",
	"lua",
	"luadoc",
	"luap",
	"markdown",
	"markdown_inline",
	"printf",
	"python",
	"query",
	"regex",
	"rust",
	"toml",
	"vim",
	"vimdoc",
	"xml",
	"yaml",
}

local function install_parsers()
	TS.install(ensure_installed)
end

-- Wait for mason-tool-installer to finish before compiling parsers
if vim.fn.executable("tree-sitter") == 1 then
	install_parsers()
else
	vim.api.nvim_create_autocmd("User", {
		pattern = "MasonToolsUpdateCompleted",
		once = true,
		callback = install_parsers,
	})
end

require("treesitter-autoinstall").setup()

local treesitter_group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
	group = treesitter_group,
	callback = function(ev)
		local lang = vim.treesitter.language.get_lang(ev.match)
		if not lang or not vim.treesitter.language.add(lang) then
			return
		end

		vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})

-- Hook
local hooks = function(ev)
	local name, kind = ev.data.spec.name, ev.data.kind
	if name == "nvim-treesitter" and (kind == "install" or kind == "update") then
		vim.cmd("TSUpdate")
	end
end
vim.api.nvim_create_autocmd("PackChanged", { callback = hooks })
