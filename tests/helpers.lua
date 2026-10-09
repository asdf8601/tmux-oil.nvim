local tmux = require("tmux-oil.tmux")

local M = {}

M.config = {
  columns = { "target", "name", "title", "cwd", "command" },
  max_width = { title = 30, cwd = 25 },
  command_alias = {},
  header = true,
}

-- Each spec is { session, window_index, window_name, command }; ids are
-- assigned in order.
function M.state(specs)
  local panes = {}
  for i, s in ipairs(specs) do
    table.insert(panes, {
      session_id = "$" .. s[1],
      session = s[1],
      window_id = "@" .. s[1] .. s[2],
      window_index = s[2],
      window_name = s[3],
      id = "%" .. i,
      title = "",
      cwd = "/tmp/" .. s[1],
      command = s[4] or "zsh",
    })
  end
  return tmux.build(panes)
end

return M
