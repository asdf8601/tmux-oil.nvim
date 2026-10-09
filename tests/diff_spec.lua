local h = dofile("tests/helpers.lua")
local view = require("tmux-oil.view")
local parse = require("tmux-oil.parse")
local diff = require("tmux-oil.diff")

local NO_CTX = { own = {} }

-- Renders the state, lets edit change the lines, and diffs the result.
local function run(state, edit, ctx)
  local lines = view.render(state, h.config)
  table.remove(lines, 1)
  lines = edit(lines) or lines
  local rows = assert(parse.parse(lines, h.config.columns))
  return diff.compute(state, rows, ctx or NO_CTX)
end

local function two_windows()
  return h.state({ { "a", 1, "editor", "nvim" }, { "a", 1, "editor" }, { "a", 2, "logs", "k9s" } })
end

test("diff: no edits is an empty plan", function()
  local plan = run(two_windows(), function() end)
  eq(true, plan.empty)
end)

test("diff: deleted line kills the pane", function()
  local plan = run(two_windows(), function(l)
    table.remove(l, 3)
  end)
  eq({ "%3" }, vim.tbl_map(function(p)
    return p.id
  end, plan.kills))
  eq("@a2", plan.destroyed[1].id)
  eq(true, plan.destructive)
end)

test("diff: changed target moves the pane", function()
  local plan = run(two_windows(), function(l)
    l[2] = l[2]:gsub("a:1", "a:2")
  end)
  eq({ { id = "%2", window = "@a2" } }, plan.moves)
  eq({}, plan.hold)
  eq(false, plan.destructive)
end)

test("diff: swapping single panes holds both windows", function()
  local plan = run(two_windows(), function(l)
    l[1] = l[1]:gsub("a:1", "a:2")
    l[2] = l[2]:gsub("a:1", "a:2")
    l[3] = l[3]:gsub("a:2", "a:1")
  end)
  eq({ "@a1", "@a2" }, plan.hold)
  eq({}, plan.destroyed)
end)

test("diff: unknown index creates one window per target", function()
  local plan = run(two_windows(), function(l)
    l[1] = "%1 a:9 | code | | | nvim"
    l[2] = "%2 a:9 | | | | zsh"
    table.insert(l, "a: | scratch | | | htop")
  end)
  eq(2, #plan.groups)
  eq({ "code", 9, false }, { plan.groups[1].name, plan.groups[1].index, plan.groups[1].new_session })
  eq({ { id = "%1" }, { id = "%2" } }, plan.groups[1].members)
  eq({ { command = "htop" } }, plan.groups[2].members)
  eq("@a1", plan.destroyed[1].id)
end)

test("diff: unknown session creates a session", function()
  local plan = run(two_windows(), function(l)
    table.insert(l, "work: | shell | | | htop")
  end)
  eq(true, plan.groups[1].new_session)
  eq("shell", plan.groups[1].name)
end)

test("diff: edited name renames the window", function()
  local plan = run(two_windows(), function(l)
    l[3] = l[3]:gsub("logs", "k8s")
  end)
  eq({ { window = "@a2", name = "k8s" } }, plan.renames)
end)

test("diff: name of a moved line is ignored", function()
  local plan = run(two_windows(), function(l)
    l[1] = "%1 a:2 | other | | | nvim"
  end)
  eq({}, plan.renames)
  eq(1, #plan.moves)
end)

test("diff: new line in existing window splits with its command", function()
  local plan = run(two_windows(), function(l)
    table.insert(l, "a:2 | | | | tail -f log | grep x")
  end)
  eq({ { window = "@a2", command = "tail -f log | grep x", cwd = "/tmp/a" } }, plan.splits)
end)

test("diff: copied line splits with the original cwd and no command", function()
  local plan = run(two_windows(), function(l)
    table.insert(l, l[3])
  end)
  eq({ { window = "@a2", command = "", cwd = "/tmp/a" } }, plan.splits)
  eq({}, plan.kills)
end)

test("diff: unknown id is an error", function()
  local plan, err = run(two_windows(), function(l)
    l[1] = "%99 a:1 | | | | zsh"
  end)
  eq(nil, plan)
  eq(true, err:find("unknown pane") ~= nil)
end)

test("diff: emptying the client session by moves follows the last moved pane", function()
  local plan = run(two_windows(), function()
    return { "%1 b: | | | | nvim", "%2 b: | | | | zsh", "%3 b: | | | | k9s" }
  end, { own = {}, client_session = "a", client = "/dev/ttys001" })
  eq({ pane = "%3", client = "/dev/ttys001", session = "a", window = "@a1" }, plan.follow)
end)

test("diff: emptying the client session by kills is refused", function()
  local plan, err = run(two_windows(), function()
    return {}
  end, { own = {}, client_session = "a" })
  eq(nil, plan)
  eq(true, err:find("client detached") ~= nil)
end)

test("diff: killing the own pane goes last and flags the plan", function()
  local plan = run(two_windows(), function(l)
    table.remove(l, 3)
    table.remove(l, 1)
  end, { own = { ["%1"] = true } })
  eq({ "%3", "%1" }, vim.tbl_map(function(p)
    return p.id
  end, plan.kills))
  eq(true, plan.own)
end)
