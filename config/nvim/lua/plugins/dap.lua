-- Debugging Protocol (DAP) - VS Code like debugging
return {
  "mfussenegger/nvim-dap",
  dependencies = {
    -- Beautiful UI for the debugger
    {
      "rcarriga/nvim-dap-ui",
      dependencies = { "nvim-neotest/nvim-nio" },
       -- stylua: ignore
      keys = {
        { "<leader>du", function() require("dapui").toggle({ }) end, desc = "Dap UI" },
        { "<leader>de", function() require("dapui").eval() end, desc = "Eval" },
      },
      opts = {},
      config = function(_, opts)
        local dap = require("dap")
        local dapui = require("dapui")
        dapui.setup(opts)
        -- Auto open/close UI when debugging starts/stops
        dap.listeners.after.event_initialized["dapui_config"] = function()
          dapui.open()
        end
        dap.listeners.before.event_terminated["dapui_config"] = function()
          dapui.close()
        end
        dap.listeners.before.event_exited["dapui_config"] = function()
          dapui.close()
        end
      end,
    },
    -- Virtual text for current line values
    {
      "theHamsta/nvim-dap-virtual-text",
      opts = {},
    },
    -- Mason integration to auto-install debuggers
    {
      "jay-babu/mason-nvim-dap.nvim",
      dependencies = "williamboman/mason.nvim",
      cmd = { "DapInstall", "DapUninstall" },
      opts = {
        automatic_installation = true,
        handlers = {}, -- use default handlers
        ensure_installed = {
          "python", 
          "delve", 
          "codelldb",
          "bash",
        },
      },
    },
  },
  keys = {
    { "<F5>", function() require("dap").continue() end, desc = "Debug: Start/Continue" },
    { "<F10>", function() require("dap").step_over() end, desc = "Debug: Step Over" },
    { "<F11>", function() require("dap").step_into() end, desc = "Debug: Step Into" },
    { "<S-F11>", function() require("dap").step_out() end, desc = "Debug: Step Out" },
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Debug: Toggle Breakpoint" },
    { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = "Debug: Conditional Breakpoint" },
  },
}
