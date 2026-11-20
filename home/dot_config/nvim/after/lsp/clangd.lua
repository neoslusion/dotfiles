-- On Windows, run Mason's clangd.exe directly: its bin/clangd.cmd wrapper goes
-- through cmd.exe, which took ~540 ms to spawn versus ~100 ms for the exe.
local function clangd_bin()
	if vim.fn.has("win32") == 1 then
		local exes = vim.fn.glob(vim.fn.stdpath("data") .. "/mason/packages/clangd/*/bin/clangd.exe", false, true)
		if #exes > 0 then
			return exes[#exes]
		end
	end
	return vim.fn.exepath("clangd")
end

---@type vim.lsp.Config
return {
	-- Auto-detect compile_commands.json in common out-of-tree build dirs.
	-- clangd only searches the source file's ancestors, so a database in
	-- e.g. Build/ (sibling of the sources) is invisible without this.
	cmd = function(dispatchers, config)
		local cmd = {
			clangd_bin(),
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
}
