local parse = require("tmux-oil.parse")
local view = require("tmux-oil.view")
local diff = require("tmux-oil.diff")

local M = {}

local hl_ns = vim.api.nvim_create_namespace("tmux-oil")
local preview_ns = vim.api.nvim_create_namespace("tmux-oil-preview")

local function prefix_of(line)
  return line:match("^%s*%%%d+ ") or ""
end

-- Byte ranges of each cell in a line, 0-based and end exclusive: s..e is the
-- whole cell between separators, ts..te its text without padding. An empty
-- cell gets ts == te on a padding space, so the cursor can land in it.
function M.ranges(line, n)
  local out, pos = {}, #prefix_of(line) + 1
  for i = 1, n do
    local sep = i < n and line:find("|", pos, true) or nil
    local stop = sep and sep - 1 or #line
    local raw = line:sub(pos, stop)
    local text = vim.trim(raw)
    local ts = pos - 1 + #raw:match("^%s*")
    if text == "" then
      ts = pos - 1 + math.max(0, math.min(1, #raw - 1))
    end
    table.insert(out, { s = pos - 1, e = stop, ts = ts, te = ts + #text })
    if not sep then
      break
    end
    pos = sep + 1
  end
  return out
end

local function cell_at(ranges, col)
  for i, r in ipairs(ranges) do
    if col <= r.e then
      return i
    end
  end
  return #ranges
end

function M.highlight(buf, hls)
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, hl_ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
end

-- Moves to the next (dir 1) or previous (dir -1) cell, wrapping to the
-- neighbour line at the ends.
function M.jump_cell(dir, n)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local ranges = M.ranges(vim.api.nvim_get_current_line(), n)
  local i = cell_at(ranges, col) + dir
  if i < 1 or i > #ranges then
    row = row + dir
    if row < 1 or row > vim.api.nvim_buf_line_count(0) then
      return
    end
    ranges = M.ranges(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1], n)
    i = dir > 0 and 1 or #ranges
  end
  vim.api.nvim_win_set_cursor(0, { row, ranges[i].ts })
end

-- Visually selects the text of the cell under the cursor, for the ic text object.
function M.select_cell(n)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local ranges = M.ranges(vim.api.nvim_get_current_line(), n)
  local r = ranges[cell_at(ranges, col)]
  vim.api.nvim_win_set_cursor(0, { row, r.ts })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { row, math.max(r.ts, r.te - 1) })
end

-- Opens a line for a new pane in the same window as the current line, with
-- the separators in place and the cursor in the command column.
function M.open_line(below, n)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local first = M.ranges(line, n)[1]
  local target = vim.trim(line:sub(first.s + 1, first.e))
  if target == "TARGET" then
    target = ""
  end
  local at = below and row or row - 1
  vim.api.nvim_buf_set_lines(0, at, at, false, { target .. string.rep(" | ", n - 1) })
  vim.api.nvim_win_set_cursor(0, { at + 1, 0 })
  vim.cmd("startinsert!")
end

-- Re-pads the columns of the edited buffer, keeping the cursor in its cell.
function M.realign(buf, columns)
  local n = #columns
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local rows = {}
  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      table.insert(rows, false)
    else
      local ranges = M.ranges(line, n)
      local cells = {}
      for i, col in ipairs(columns) do
        local r = ranges[i]
        cells[col] = r and line:sub(r.ts + 1, r.te) or ""
      end
      local prefix = prefix_of(line)
      table.insert(rows, { prefix = prefix, cells = cells, header = prefix == "" and cells.target == "TARGET" })
    end
  end
  local new, hls = view.format(rows, columns)
  if vim.deep_equal(lines, new) then
    return
  end

  local win = vim.fn.bufwinid(buf)
  local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win)
  local cell, offset
  if cursor then
    local ranges = M.ranges(lines[cursor[1]], n)
    cell = cell_at(ranges, cursor[2])
    offset = math.max(0, cursor[2] - ranges[cell].ts)
  end

  -- Joined to the edit that caused it, so one undo reverts both.
  pcall(vim.cmd, "undojoin")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
  M.highlight(buf, hls)
  if cursor then
    local r = M.ranges(new[cursor[1]], n)[cell]
    vim.api.nvim_win_set_cursor(win, { cursor[1], r and math.min(r.ts + offset, math.max(r.ts, r.te)) or 0 })
  end
end

-- Shows next to each line what :w would do with it.
function M.preview(buf, state, ctx, columns)
  vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
  if not state then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local function note(lnum, text, group)
    lnum = math.min(math.max(lnum, 1), count)
    vim.api.nvim_buf_set_extmark(buf, preview_ns, lnum - 1, 0, { virt_text = { { "  " .. text, group } }, virt_text_pos = "eol" })
  end
  local function fail(err)
    note(tonumber(err:match("^line (%d+)")) or 1, "✗ " .. err, "DiagnosticError")
  end

  local rows, err = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), columns)
  if not rows then
    return fail(err)
  end
  local plan
  plan, err = diff.compute(state, rows, ctx)
  if not plan then
    return fail(err)
  end
  for lnum, n in pairs(plan.notes) do
    note(lnum, n[1], n[2])
  end
  local summary = diff.summary(plan)
  if summary ~= "" then
    note(1, summary, "DiagnosticError")
  end
end

function M.attach(buf, config, get)
  local n = #config.columns
  local function map(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, silent = true, desc = "tmux-oil: " .. desc })
  end
  map({ "n", "i" }, "<Tab>", function()
    M.jump_cell(1, n)
  end, "next cell")
  map({ "n", "i" }, "<S-Tab>", function()
    M.jump_cell(-1, n)
  end, "previous cell")
  map({ "o", "x" }, "ic", ":<C-u>lua require('tmux-oil.edit').select_cell(" .. n .. ")<CR>", "inside cell")
  map("n", "o", function()
    M.open_line(true, n)
  end, "new pane below")
  map("n", "O", function()
    M.open_line(false, n)
  end, "new pane above")

  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = buf,
    callback = function()
      M.realign(buf, config.columns)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      local state, ctx = get()
      M.preview(buf, state, ctx, config.columns)
    end,
  })
end

return M
