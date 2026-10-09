local M = {}

function M.apply(plan, tmux)
  local trash, created = {}, {}

  local function run(args)
    local out, err = tmux.run(args)
    if not out then
      error(err, 0)
    end
    return out
  end

  -- -l sends the text literally; otherwise a command like "Up" is read as a key.
  local function send(pane, command)
    if command ~= "" then
      run({ "send-keys", "-t", pane, "-l", command })
      run({ "send-keys", "-t", pane, "Enter" })
    end
  end

  local function split(window, cwd)
    local args = { "split-window", "-d", "-t", window, "-P", "-F", "#{pane_id}" }
    if cwd then
      vim.list_extend(args, { "-c", cwd })
    end
    return run(args)
  end

  local function create(g)
    local first_new
    for _, m in ipairs(g.members) do
      if not m.id then
        first_new = m
        break
      end
    end
    local args
    if g.new_session and not created[g.session] then
      created[g.session] = true
      args = { "new-session", "-d", "-s", g.session }
    else
      args = { "new-window", "-d", "-t", g.session .. ":" .. (g.index or "") }
    end
    if g.name ~= "" then
      vim.list_extend(args, { "-n", g.name })
    end
    if first_new and first_new.cwd then
      vim.list_extend(args, { "-c", first_new.cwd })
    end
    vim.list_extend(args, { "-P", "-F", "#{window_id} #{pane_id}" })
    local out, err = tmux.run(args)
    if not out and g.index and args[1] == "new-window" then
      -- The index is a hint: fall back to the next free one.
      args[4] = g.session .. ":"
      out, err = tmux.run(args)
    end
    if not out then
      error(err, 0)
    end
    return out:match("^(%S+) (%S+)$")
  end

  local ok, err = pcall(function()
    -- A placeholder keeps each surviving window alive while its panes move
    -- around, so moves can run in any order, swaps included.
    for _, w in ipairs(plan.hold) do
      table.insert(trash, run({ "split-window", "-d", "-t", w, "-P", "-F", "#{pane_id}", "cat" }))
    end
    for _, g in ipairs(plan.groups) do
      local window, initial = create(g)
      local used = false
      for _, m in ipairs(g.members) do
        if m.id then
          run({ "join-pane", "-d", "-s", m.id, "-t", window })
        elseif not used then
          used = true
          send(initial, m.command)
        else
          send(split(window, m.cwd), m.command)
        end
      end
      if not used then
        table.insert(trash, initial)
      end
    end
    for _, m in ipairs(plan.moves) do
      run({ "join-pane", "-d", "-s", m.id, "-t", m.window })
    end
    for _, s in ipairs(plan.splits) do
      send(split(s.window, s.cwd), s.command)
    end
    for _, r in ipairs(plan.renames) do
      run({ "rename-window", "-t", r.window, r.name })
    end
    for _, p in ipairs(plan.kills) do
      if p.own then
        break
      end
      run({ "kill-pane", "-t", p.id })
    end
  end)

  for _, pane in ipairs(trash) do
    tmux.run({ "kill-pane", "-t", pane })
  end
  if not ok then
    return false, err
  end
  for _, p in ipairs(plan.kills) do
    if p.own then
      tmux.run({ "kill-pane", "-t", p.id })
    end
  end
  return true
end

return M
