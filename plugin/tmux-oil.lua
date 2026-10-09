vim.api.nvim_create_user_command("TmuxOil", function()
  require("tmux-oil").open()
end, { desc = "Edit tmux sessions, windows and panes as a buffer" })
