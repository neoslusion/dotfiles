-- On Windows, run Mason's rust-analyzer.exe directly instead of its .cmd
-- wrapper, which spawns through cmd.exe (~5x slower to start). nil keeps
-- lspconfig's default command.
local exe = vim.fn.stdpath("data") .. "/mason/packages/rust-analyzer/rust-analyzer.exe"
local cmd = (vim.fn.has("win32") == 1 and vim.uv.fs_stat(exe)) and { exe } or nil

return {
	cmd = cmd,
	settings = { ["rust-analyzer"] = { checkOnSave = { command = "clippy" } } },
}
