local tmux = require("tmux-oil.tmux")

local M = {}

M.config = {
  max_width = { title = 30, cwd = 25 },
  command_alias = {},
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

-- Diff and apply tests edit a flat form, one "%id session:index | name |
-- command" line per pane, which is easier to change by line number than the
-- tree.
function M.flat(state)
  local lines, named = {}, {}
  for _, p in ipairs(state.panes) do
    local name = named[p.window_id] and "" or p.window_name
    named[p.window_id] = true
    table.insert(lines, ("%s %s:%d | %s | %s"):format(p.id, p.session, p.window_index, name, p.command))
  end
  return lines
end

function M.rows(lines)
  local rows = {}
  for lnum, line in ipairs(lines) do
    local id, rest = line:match("^(%%%d+) (.*)$")
    local target, name, command = (rest or line):match("^(.-)%s*|%s*(.-)%s*|%s*(.*)$")
    local session, index = target:match("^([^:]+):(%d*)$")
    table.insert(rows, { lnum = lnum, id = id, target = target, session = session, index = tonumber(index), name = name, command = command })
  end
  return rows
end

return M
