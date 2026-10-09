local tmux = require("tmux-oil.tmux")
local view = require("tmux-oil.view")
local parse = require("tmux-oil.parse")
local diff = require("tmux-oil.diff")
local apply = require("tmux-oil.apply")

local M = {}

M.config = {
  columns = { "target", "name", "title", "cwd", "command" },
  max_width = { title = 30, cwd = 25 },
  confirm = "destructive",
  close_on_switch = false,
  command_alias = {},
  header = true,
  socket = nil,
}

local NAME = "tmux-oil://"
local ns = vim.api.nvim_create_namespace("tmux-oil")
local snapshots = {}

local function notify(msg, level)
  vim.notify("tmux-oil: " .. msg, level or vim.log.levels.ERROR)
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)
  if opts.columns then
    M.config.columns = opts.columns
  end
  local cols = M.config.columns
  assert(vim.list_contains(cols, "target"), "tmux-oil: columns must include target")
  assert(cols[#cols] == "command", "tmux-oil: command must be the last column")
  tmux.socket = M.config.socket
end

local function context(state)
  local own = {}
  if vim.env.TMUX_PANE and state.by_id[vim.env.TMUX_PANE] then
    own[vim.env.TMUX_PANE] = true
  end
  if not vim.env.TMUX or tmux.socket then
    return { own = own }
  end
  -- Inside display-popup $TMUX_PANE is not the parent pane; the client's
  -- active pane is.
  local active = tmux.run({ "display-message", "-p", "#{pane_id}" })
  if active and state.by_id[active] then
    own[active] = true
  end
  return { own = own, client_session = tmux.run({ "display-message", "-p", "#{session_name}" }) }
end

local function stale(old, new)
  for _, p in ipairs(old.panes) do
    local q = new.by_id[p.id]
    if not q or q.window_id ~= p.window_id then
      return true
    end
  end
  return false
end

local function render(buf)
  local state, err = tmux.read()
  if not state then
    return notify(err)
  end
  snapshots[buf] = state
  local lines, hls = view.render(state, M.config)
  local undolevels = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].undolevels = undolevels
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
end

local function write(buf)
  local state = snapshots[buf]
  local rows, err = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false), M.config.columns)
  if not rows then
    return notify(err)
  end
  local plan
  plan, err = diff.compute(state, rows, context(state))
  if not plan then
    return notify(err)
  end
  if plan.empty then
    vim.bo[buf].modified = false
    return
  end
  local fresh = tmux.read()
  if not fresh or stale(state, fresh) then
    return notify("tmux changed since the buffer was rendered, press R to refresh")
  end
  local confirm = M.config.confirm
  if plan.own or confirm == "always" or (confirm == "destructive" and plan.destructive) then
    local msg = table.concat(diff.describe(plan, state), "\n")
    if vim.fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then
      return
    end
  end
  local ok
  ok, err = apply.apply(plan, tmux)
  if not ok then
    notify(err)
  end
  render(buf)
end

local function jump(buf)
  local id = parse.id(vim.api.nvim_get_current_line())
  if not id then
    return
  end
  for _, cmd in ipairs({ "select-window", "select-pane", "switch-client" }) do
    local _, err = tmux.run({ cmd, "-t", id })
    if err then
      return notify(err)
    end
  end
  if vim.b[buf].tmux_oil_close then
    vim.cmd("qa!")
  end
end

local function create()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, NAME)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "tmux-oil"
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[syntax match TmuxOilId /^\s*%\d\+ / conceal]])
    vim.cmd([[syntax match TmuxOilSep /|/]])
    vim.cmd([[highlight default link TmuxOilSep NonText]])
  end)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      write(buf)
    end,
  })
  -- The id is concealed but still text; keep the cursor after it so edits at
  -- the start of the line change the target, not the id.
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    buffer = buf,
    callback = function()
      local prefix = vim.api.nvim_get_current_line():match("^%s*%%%d+ ")
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      if prefix and col < #prefix then
        vim.api.nvim_win_set_cursor(0, { row, #prefix })
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      snapshots[buf] = nil
    end,
  })
  vim.keymap.set("n", "<CR>", function()
    jump(buf)
  end, { buffer = buf, desc = "tmux-oil: switch to pane" })
  vim.keymap.set("n", "R", function()
    render(buf)
  end, { buffer = buf, desc = "tmux-oil: refresh" })
  return buf
end

function M.open(opts)
  opts = opts or {}
  local buf = vim.fn.bufnr(NAME)
  if buf == -1 then
    buf = create()
  end
  vim.api.nvim_set_current_buf(buf)
  vim.wo.conceallevel = 3
  vim.wo.concealcursor = "nvic"
  vim.wo.wrap = false
  vim.b[buf].tmux_oil_close = vim.F.if_nil(opts.close_on_switch, M.config.close_on_switch)
  render(buf)
end

return M
