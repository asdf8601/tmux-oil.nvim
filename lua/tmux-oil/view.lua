local M = {}

local function truncate(s, max, from_left)
  if not max or vim.fn.strchars(s) <= max then
    return s
  end
  if from_left then
    return "…" .. vim.fn.strcharpart(s, vim.fn.strchars(s) - max + 1)
  end
  return vim.fn.strcharpart(s, 0, max - 1) .. "…"
end

local function pad(s, width)
  return s .. string.rep(" ", width - vim.fn.strdisplaywidth(s))
end

-- The text after the hidden id of a pane line: command, title and cwd. It is
-- only a label, parse ignores it for existing panes.
local function label(p, cfg, env)
  local command = p.command
  for pattern, alias in pairs(cfg.command_alias) do
    if command:match(pattern) then
      command = alias
      break
    end
  end
  local cwd = p.cwd
  if env.home ~= "" and vim.startswith(cwd, env.home) then
    cwd = "~" .. cwd:sub(#env.home + 1)
  end
  return {
    command,
    truncate(p.title == env.hostname and "" or p.title, cfg.max_width.title),
    truncate(cwd, cfg.max_width.cwd, true),
  }
end

-- Renders a tree: "# session", "  index: name" and one line per pane.
function M.render(state, cfg)
  local env = {
    hostname = (vim.uv.os_gethostname():gsub("%..*", "")),
    home = vim.env.HOME or "",
  }
  local labels, widths = {}, { 0, 0 }
  for i, p in ipairs(state.panes) do
    labels[i] = label(p, cfg, env)
    for c = 1, 2 do
      widths[c] = math.max(widths[c], vim.fn.strdisplaywidth(labels[i][c]))
    end
  end

  local lines, session, window = {}, nil, nil
  for i, p in ipairs(state.panes) do
    if p.session ~= session then
      session = p.session
      table.insert(lines, "# " .. session)
    end
    if p.window_id ~= window then
      window = p.window_id
      table.insert(lines, ("  %d: %s"):format(p.window_index, p.window_name))
    end
    local l = labels[i]
    local text = pad(l[1], widths[1]) .. "  " .. pad(l[2], widths[2]) .. "  " .. l[3]
    table.insert(lines, "    " .. p.id .. " " .. (text:gsub("%s+$", "")))
  end
  return lines
end

return M
