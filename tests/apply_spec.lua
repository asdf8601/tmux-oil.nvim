local h = dofile("tests/helpers.lua")
local tmux = require("tmux-oil.tmux")
local diff = require("tmux-oil.diff")
local apply = require("tmux-oil.apply")

if vim.fn.executable("tmux") == 0 then
  return
end

-- Session a: window 1 with two panes, window 2 with one. Session b: one window.
local function server()
  tmux.socket = "tmux-oil-test"
  tmux.run({ "kill-server" })
  assert(tmux.run({ "-f", "/dev/null", "new-session", "-d", "-s", "a", "-n", "one", "-x", "200", "-y", "50", "/bin/sh" }))
  assert(tmux.run({ "set", "-g", "default-shell", "/bin/sh" }))
  assert(tmux.run({ "move-window", "-s", "a:0", "-t", "a:1" }))
  assert(tmux.run({ "split-window", "-d", "-t", "a:1" }))
  assert(tmux.run({ "new-window", "-d", "-t", "a:2", "-n", "two", "-c", "/tmp" }))
  assert(tmux.run({ "new-session", "-d", "-s", "b", "-n", "three" }))
end

local function teardown()
  tmux.run({ "kill-server" })
  tmux.socket = nil
end

-- Renders the live state, edits it, and applies the result.
local function edit(fn)
  local state = assert(tmux.read())
  local lines = h.flat(state)
  lines = fn(lines, state) or lines
  local rows = assert(h.rows(lines))
  local plan = assert(diff.compute(state, rows, { own = {} }))
  local ok, err = apply.apply(plan, tmux)
  assert(ok, err)
  return assert(tmux.read())
end

local function layout(state)
  local out = {}
  for _, p in ipairs(state.panes) do
    local key = p.session .. ":" .. p.window_index .. " " .. p.window_name
    out[key] = (out[key] or 0) + 1
  end
  return out
end

local function with_server(name, fn)
  test(name, function()
    server()
    local ok, err = pcall(fn)
    teardown()
    assert(ok, err)
  end)
end

with_server("apply: move a pane to another session's window", function()
  local state = edit(function(l)
    l[2] = l[2]:gsub("a:1", "b:0")
  end)
  eq({ ["a:1 one"] = 1, ["a:2 two"] = 1, ["b:0 three"] = 2 }, layout(state))
end)

with_server("apply: swap the only panes of two windows", function()
  local before = assert(tmux.read())
  local state = edit(function(l)
    l[3] = l[3]:gsub("a:2", "b:0")
    l[4] = l[4]:gsub("b:0", "a:2")
  end)
  eq({ ["a:1 one"] = 2, ["a:2 two"] = 1, ["b:0 three"] = 1 }, layout(state))
  eq(before.panes[3].id, state.panes[4].id)
  eq(before.panes[4].id, state.panes[3].id)
end)

with_server("apply: break panes into a new named window", function()
  local state = edit(function(l)
    l[1] = l[1]:gsub("a:1(%s*)| one", "a:7%1| code")
    l[2] = l[2]:gsub("a:1", "a:7")
  end)
  eq({ ["a:7 code"] = 2, ["a:2 two"] = 1, ["b:0 three"] = 1 }, layout(state))
end)

with_server("apply: new window without index takes a free one", function()
  local state = edit(function(l)
    table.insert(l, "b: | extra | ")
  end)
  eq(1, layout(state)["b:1 extra"])
end)

with_server("apply: new session runs the command", function()
  edit(function(l)
    table.insert(l, "work: | shell | echo $((40 + 2))-marker")
  end)
  local found = vim.wait(3000, function()
    local out = tmux.run({ "capture-pane", "-p", "-t", "work:" })
    return out and out:find("42%-marker") ~= nil
  end, 50)
  eq(true, found)
end)

with_server("apply: rename and kill", function()
  local state = edit(function(l)
    l[3] = l[3]:gsub("| two", "| logs")
    table.remove(l, 2)
  end)
  eq({ ["a:1 one"] = 1, ["a:2 logs"] = 1, ["b:0 three"] = 1 }, layout(state))
end)

with_server("apply: a failure stops and cleans up placeholders", function()
  local state = assert(tmux.read())
  local lines = h.flat(state)
  lines[3] = lines[3]:gsub("a:2", "b:0")
  lines[4] = lines[4]:gsub("b:0", "a:2")
  local plan = assert(diff.compute(state, assert(h.rows(lines)), { own = {} }))
  table.insert(plan.renames, { window = "@999", name = "x" })
  local ok = apply.apply(plan, tmux)
  eq(false, ok)
  eq(4, #assert(tmux.read()).panes)
end)

with_server("apply: new line in an existing window runs its command in the same cwd", function()
  local state = edit(function(l)
    table.insert(l, "a:2 | | echo $((40 + 2))-marker")
  end)
  eq(2, layout(state)["a:2 two"])
  local panes = vim.tbl_filter(function(p)
    return p.window_id == state.by_target["a:2"]
  end, state.panes)
  eq(panes[1].cwd, panes[2].cwd)
  eq(true, vim.endswith(panes[1].cwd, "/tmp"))
  local found = vim.wait(3000, function()
    for _, p in ipairs(panes) do
      local out = tmux.run({ "capture-pane", "-p", "-t", p.id })
      if out and out:find("42%-marker") then
        return true
      end
    end
  end, 50)
  eq(true, found)
end)

with_server("apply: new session with two windows in one write", function()
  local state = edit(function(l)
    table.insert(l, "work:1 | one | ")
    table.insert(l, "work:2 | two | ")
  end)
  local got = layout(state)
  eq(1, got["work:0 one"] or got["work:1 one"])
  eq(true, (got["work:1 two"] or got["work:2 two"]) == 1)
  eq(2, #vim.tbl_filter(function(p)
    return p.session == "work"
  end, state.panes))
end)

-- A real client attached to session a, running inside a second server.
with_server("apply: moving the client's last pane away switches the client and drops the session", function()
  tmux.run({ "kill-session", "-t", "b" })
  assert(tmux.run({ "new-session", "-d", "-s", "b", "-n", "three" }))
  assert(tmux.run({ "kill-pane", "-t", "a:1.1" }))
  assert(tmux.run({ "kill-window", "-t", "a:2" }))
  local ui = vim.system({ "tmux", "-L", "tmux-oil-test-ui", "-f", "/dev/null", "new-session", "-d", "-x", "200", "-y", "50",
    "env -u TMUX tmux -L tmux-oil-test attach -t a" }):wait()
  assert(ui.code == 0, ui.stderr)
  local ok, err = pcall(function()
    local client = nil
    vim.wait(3000, function()
      client = tmux.run({ "list-clients", "-F", "#{client_name}" })
      return client and client ~= ""
    end, 50)
    assert(client and client ~= "", "client did not attach")
    local state = assert(tmux.read())
    local lines = h.flat(state)
    lines[1] = lines[1]:gsub("a:1", "b:0")
    local plan = assert(diff.compute(state, assert(h.rows(lines)), { own = {}, client_session = "a", client = client }))
    assert(apply.apply(plan, tmux))
    eq("b", tmux.run({ "list-clients", "-F", "#{client_session}" }))
    eq(nil, tmux.run({ "has-session", "-t", "a" }))
    eq(2, #vim.split(tmux.run({ "list-panes", "-t", "b:0", "-F", "#{pane_id}" }), "\n"))
  end)
  vim.system({ "tmux", "-L", "tmux-oil-test-ui", "kill-server" }):wait()
  assert(ok, err)
end)
