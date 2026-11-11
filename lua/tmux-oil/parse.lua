local M = {}

-- Reads the hidden pane id at the start of a line: "    %7 zsh" is pane "%7".
function M.id(line)
  local id, rest = line:match("^%s*(%%%d+)%s*(.*)$")
  if not id then
    return nil, line
  end
  return id, rest
end

-- Lines are told apart by their content, indentation is cosmetic:
--   "# name"       a session
--   "index: name"  a window of the session above, a new one without index
--   "%id label"    an existing pane of the window above, the label is ignored
--   anything else  a new pane, the text is its command
function M.parse(lines)
  local rows, session, win = {}, nil, {}
  for lnum, line in ipairs(lines) do
    local id, rest = M.id(line)
    local text = vim.trim(rest)
    local index, name = text:match("^(%d*):%s*(.*)$")
    if id or (text ~= "" and not text:match("^#") and not index) then
      if rest:find("%s%%%d+%s") then
        return nil, ("line %d: more than one pane id, was it joined with J?"):format(lnum)
      end
      if not session then
        return nil, ("line %d: pane above the first # session line"):format(lnum)
      end
      table.insert(rows, {
        lnum = lnum,
        id = id,
        session = session,
        index = win.index,
        window_lnum = win.lnum,
        target = session .. ":" .. (win.index or ""),
        name = win.name or "",
        command = text,
      })
    elseif index then
      win = { index = tonumber(index), name = name, lnum = lnum }
    elseif text ~= "" then
      session = vim.trim(text:sub(2))
      win = {}
      if session == "" then
        return nil, ("line %d: session without a name"):format(lnum)
      end
    end
  end
  return rows
end

return M
