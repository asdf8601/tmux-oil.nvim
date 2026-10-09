local M = {}

-- Splits on the first n-1 separators only, so the last column may contain "|".
local function split_cells(s, n)
  local cells, pos = {}, 1
  for _ = 1, n - 1 do
    local sep = s:find("|", pos, true)
    if not sep then
      break
    end
    table.insert(cells, vim.trim(s:sub(pos, sep - 1)))
    pos = sep + 1
  end
  table.insert(cells, vim.trim(s:sub(pos)))
  return cells
end

function M.parse(lines, columns)
  local rows = {}
  for lnum, line in ipairs(lines) do
    if not line:match("^%s*$") then
      local id, rest = line:match("^%s*(%%%d+)%s+(.*)$")
      rest = rest or line
      if rest:find("%s%%%d+%s") then
        return nil, ("line %d: more than one pane id, was it joined with J?"):format(lnum)
      end
      local cells = split_cells(rest, #columns)
      local row = { lnum = lnum, id = id }
      for i, col in ipairs(columns) do
        row[col] = cells[i] or ""
      end
      row.name = row.name or ""
      if id or row.target ~= "TARGET" then
        local session, index = row.target:match("^([^:]+):(%d*)$")
        if not session then
          return nil, ("line %d: invalid target %q, expected session:index"):format(lnum, row.target)
        end
        row.session = session
        row.index = tonumber(index)
        table.insert(rows, row)
      end
    end
  end
  return rows
end

return M
