local M = {}

M.HEADER = { target = "TARGET", name = "NAME", title = "TITLE", cwd = "CWD", command = "COMMAND" }

local GROUPS = { target = "Identifier", name = "Title", title = "Comment", cwd = "Comment" }

local function truncate(s, max, from_left)
  if not max or vim.fn.strchars(s) <= max then
    return s
  end
  if from_left then
    return "…" .. vim.fn.strcharpart(s, vim.fn.strchars(s) - max + 1)
  end
  return vim.fn.strcharpart(s, 0, max - 1) .. "…"
end

local function cells(p, first, cfg, env)
  local command = p.command
  for pattern, alias in pairs(cfg.command_alias) do
    if command:match(pattern) then
      command = alias
      break
    end
  end
  local title = p.title == env.hostname and "" or p.title
  local cwd = p.cwd
  if env.home ~= "" and vim.startswith(cwd, env.home) then
    cwd = "~" .. cwd:sub(#env.home + 1)
  end
  return {
    target = p.session .. ":" .. p.window_index,
    name = first and p.window_name or "",
    title = truncate((title:gsub("|", "¦")), cfg.max_width.title),
    cwd = truncate((cwd:gsub("|", "¦")), cfg.max_width.cwd, true),
    command = command,
  }
end

-- Aligns rows into lines. A row is { prefix, cells, header } or false for a
-- blank line. Returns the lines and highlights as { line, start_col, end_col, group }.
function M.format(rows, columns)
  local widths = {}
  for _, row in ipairs(rows) do
    if row then
      for i, col in ipairs(columns) do
        widths[i] = math.max(widths[i] or 0, vim.fn.strdisplaywidth(row.cells[col]))
      end
    end
  end

  local lines, hls = {}, {}
  for lnum, row in ipairs(rows) do
    local line = row and row.prefix or ""
    for i, col in ipairs(row and columns or {}) do
      local text = row.cells[col]
      if i < #columns then
        text = text .. string.rep(" ", widths[i] - vim.fn.strdisplaywidth(text))
      end
      local group = row.header and "Comment" or GROUPS[col]
      if group and #text > 0 then
        table.insert(hls, { lnum - 1, #line, #line + #text, group })
      end
      line = line .. text .. (i < #columns and " | " or "")
    end
    table.insert(lines, line)
  end
  return lines, hls
end

function M.render(state, cfg)
  local env = {
    hostname = (vim.uv.os_gethostname():gsub("%..*", "")),
    home = vim.env.HOME or "",
  }
  local id_width = 0
  for _, p in ipairs(state.panes) do
    id_width = math.max(id_width, #p.id - 1)
  end

  local rows = {}
  if cfg.header then
    table.insert(rows, { prefix = "", cells = M.HEADER, header = true })
  end
  local named = {}
  for _, p in ipairs(state.panes) do
    local prefix = ("%%%0" .. id_width .. "d "):format(tonumber(p.id:sub(2)))
    table.insert(rows, { prefix = prefix, cells = cells(p, not named[p.window_id], cfg, env) })
    named[p.window_id] = true
  end
  return M.format(rows, cfg.columns)
end

return M
