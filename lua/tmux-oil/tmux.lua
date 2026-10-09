local M = {}

M.socket = nil

local SEP = "\31"
local FIELDS = {
  "session_id",
  "session_name",
  "window_id",
  "window_index",
  "window_name",
  "pane_id",
  "pane_title",
  "pane_current_path",
  "pane_current_command",
}

function M.run(args)
  local cmd = { "tmux" }
  if M.socket then
    vim.list_extend(cmd, { "-L", M.socket })
  end
  vim.list_extend(cmd, args)
  local res = vim.system(cmd, { text = true }):wait()
  if res.code ~= 0 then
    local err = vim.trim(res.stderr or "")
    return nil, ("tmux %s: %s"):format(args[1], err)
  end
  return vim.trim(res.stdout or "")
end

-- Builds the lookup tables used by view and diff from a flat list of panes.
function M.build(panes)
  local state = { panes = panes, by_id = {}, windows = {}, window_list = {}, by_target = {}, sessions = {} }
  for _, p in ipairs(panes) do
    state.by_id[p.id] = p
    state.sessions[p.session] = p.session_id
    local w = state.windows[p.window_id]
    if not w then
      w = { id = p.window_id, session = p.session, index = p.window_index, name = p.window_name, cwd = p.cwd }
      state.windows[p.window_id] = w
      table.insert(state.window_list, w)
      state.by_target[p.session .. ":" .. p.window_index] = p.window_id
    end
  end
  return state
end

function M.read()
  local fmt = vim.tbl_map(function(f)
    return "#{" .. f .. "}"
  end, FIELDS)
  local out, err = M.run({ "list-panes", "-a", "-F", table.concat(fmt, SEP) })
  if not out then
    return nil, err
  end
  local panes = {}
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local v = vim.split(line, SEP, { plain = true })
    table.insert(panes, {
      session_id = v[1],
      session = v[2],
      window_id = v[3],
      window_index = tonumber(v[4]),
      window_name = v[5],
      id = v[6],
      title = v[7],
      cwd = v[8],
      command = v[9],
    })
  end
  return M.build(panes)
end

return M
