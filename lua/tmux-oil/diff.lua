local M = {}

-- Turns the parsed buffer into a plan of tmux operations, relative to the
-- snapshot taken when the buffer was rendered.
--
-- ctx.own: set of pane ids where this nvim runs.
-- ctx.client_session: name of the session the client is attached to.
-- ctx.client: name of that client.
function M.compute(state, rows, ctx)
  local plan = { groups = {}, moves = {}, splits = {}, renames = {}, kills = {}, hold = {}, destroyed = {}, own = false }
  local seen, count, loses, renamed, by_key = {}, {}, {}, {}, {}
  local last_moved
  local original = {}
  for _, p in ipairs(state.panes) do
    original[p.window_id] = (original[p.window_id] or 0) + 1
  end

  local function lose(window)
    loses[window] = (loses[window] or 0) + 1
  end

  local function add_to_group(row, member)
    local key = row.session .. ":" .. (row.index or "")
    local g = by_key[key]
    if not g then
      g = { session = row.session, index = row.index, name = "", new_session = not state.sessions[row.session], members = {} }
      by_key[key] = g
      table.insert(plan.groups, g)
    end
    if g.name == "" then
      g.name = row.name
    end
    table.insert(g.members, member)
  end

  for _, row in ipairs(rows) do
    local pane = row.id and state.by_id[row.id]
    if row.id and not pane then
      return nil, ("line %d: unknown pane %s"):format(row.lnum, row.id)
    end
    local win = row.index and state.by_target[row.session .. ":" .. row.index]
    if win then
      count[win] = (count[win] or 0) + 1
    end

    if pane and not seen[row.id] then
      seen[row.id] = true
      if win == pane.window_id then
        if row.name ~= "" and row.name ~= state.windows[win].name and not renamed[win] then
          renamed[win] = true
          table.insert(plan.renames, { window = win, name = row.name })
        end
      else
        lose(pane.window_id)
        last_moved = row.id
        plan.own = plan.own or ctx.own[row.id] == true
        if win then
          table.insert(plan.moves, { id = row.id, window = win })
        else
          add_to_group(row, { id = row.id })
        end
      end
    else
      -- A new line, or a copy of an existing one (yyp keeps the hidden id).
      local member = { command = pane and "" or row.command, cwd = pane and pane.cwd }
      if win then
        table.insert(plan.splits, { window = win, command = member.command, cwd = member.cwd or state.windows[win].cwd })
      else
        add_to_group(row, member)
      end
    end
  end

  for _, p in ipairs(state.panes) do
    if not seen[p.id] then
      local own = ctx.own[p.id] == true
      table.insert(plan.kills, vim.tbl_extend("force", p, { own = own }))
      lose(p.window_id)
      plan.own = plan.own or own
    end
  end
  -- Killing the pane nvim runs in ends the apply, so it goes last.
  table.sort(plan.kills, function(a, b)
    return not a.own and b.own
  end)

  local alive = {}
  for _, g in ipairs(plan.groups) do
    alive[g.session] = true
  end
  for _, w in ipairs(state.window_list) do
    if count[w.id] then
      alive[w.session] = true
      -- Only a window that loses every original pane can vanish mid-apply.
      if loses[w.id] == original[w.id] then
        table.insert(plan.hold, w.id)
      end
    else
      table.insert(plan.destroyed, w)
    end
  end
  -- When the client's session empties, tmux would detach the client. Follow
  -- the last moved pane instead; with nothing moved there is nowhere to go.
  if ctx.client_session and state.sessions[ctx.client_session] and not alive[ctx.client_session] then
    if not last_moved then
      return nil, ("session %s would be destroyed and the client detached"):format(ctx.client_session)
    end
    plan.follow = { pane = last_moved, client = ctx.client, session = ctx.client_session }
    for _, w in ipairs(state.window_list) do
      if w.session == ctx.client_session then
        plan.follow.window = w.id
        break
      end
    end
  end

  plan.destructive = #plan.kills > 0 or #plan.destroyed > 0
  plan.empty = #plan.groups + #plan.moves + #plan.splits + #plan.renames + #plan.kills == 0
  return plan
end

local function target(state, window)
  local w = state.windows[window]
  return w.session .. ":" .. w.index
end

function M.describe(plan, state)
  local out = {}
  for _, g in ipairs(plan.groups) do
    local where = g.session .. ":" .. (g.index or "")
    table.insert(out, ("create %s %s %s"):format(g.new_session and "session" or "window", where, g.name))
    for _, m in ipairs(g.members) do
      if m.id then
        table.insert(out, ("  move %s (%s)"):format(m.id, state.by_id[m.id].command))
      else
        table.insert(out, ("  new pane %s"):format(m.command))
      end
    end
  end
  for _, m in ipairs(plan.moves) do
    table.insert(out, ("move %s (%s) to %s"):format(m.id, state.by_id[m.id].command, target(state, m.window)))
  end
  for _, s in ipairs(plan.splits) do
    table.insert(out, ("new pane in %s %s"):format(target(state, s.window), s.command))
  end
  for _, r in ipairs(plan.renames) do
    table.insert(out, ("rename %s to %s"):format(target(state, r.window), r.name))
  end
  for _, p in ipairs(plan.kills) do
    table.insert(out, ("kill %s (%s in %s:%d)"):format(p.id, p.command, p.session, p.window_index))
  end
  for _, w in ipairs(plan.destroyed) do
    table.insert(out, ("window %s:%d %s will be destroyed"):format(w.session, w.index, w.name))
  end
  if plan.follow then
    table.insert(out, ("session %s will be destroyed, the client follows %s"):format(plan.follow.session, plan.follow.pane))
  end
  if plan.own then
    table.insert(out, "this changes the pane where nvim is running")
  end
  return out
end

return M
