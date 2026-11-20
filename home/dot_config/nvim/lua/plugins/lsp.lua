local ensure_installed = {
	"tree-sitter-cli",
	"stylua",
	"shellcheck",
	"shfmt",
	"clangd",
	"rust-analyzer",
}

if vim.fn.executable("npm") == 1 then
	vim.list_extend(ensure_installed, { "pyright" })
end

require("mason").setup()
require("mason-tool-installer").setup({
	ensure_installed = ensure_installed,
	auto_update = false,
	run_on_start = true,
})

local capabilities = {
	workspace = {
		fileOperations = {
			didRename = true,
			willRename = true,
		},
	},
}
vim.lsp.config("*", {
	capabilities = require("blink.cmp").get_lsp_capabilities(capabilities),
})

local servers = { "clangd", "rust_analyzer" }
if vim.fn.executable("npm") == 1 then
	vim.list_extend(servers, { "pyright" })
end

-- Start servers after the first screen is drawn: spawning a server process
-- blocks the UI on Windows, so opening a file shows its contents first.
vim.schedule(function()
	vim.lsp.enable(servers)
end)
