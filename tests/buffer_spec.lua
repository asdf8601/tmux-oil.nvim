local tmux = require("tmux-oil.tmux")

if vim.fn.executable("tmux") == 0 then
  return
end

-- Drives a real nvim inside the test server, so autocmds run between keys as
-- they do when a person types. Session a: window 0 with two panes. Session
-- ui: the nvim with the buffer open.
local function with_nvim(name, fn)
  test(name, function()
    tmux.socket = "tmux-oil-test"
    tmux.run({ "kill-server" })
    assert(tmux.run({ "-f", "/dev/null", "new-session", "-d", "-s", "a", "-x", "200", "-y", "50", "/bin/sh" }))
    assert(tmux.run({ "set", "-g", "default-shell", "/bin/sh" }))
    assert(tmux.run({ "split-window", "-d", "-t", "a:0" }))
    local setup = "lua require('tmux-oil').setup({ socket = 'tmux-oil-test', confirm = 'never' }) require('tmux-oil').open()"
    local nvim = ("nvim -u NONE -i NONE --cmd 'set rtp^=%s' -c \"%s\""):format(vim.fn.getcwd(), setup)
    assert(tmux.run({ "new-session", "-d", "-s", "ui", "-x", "200", "-y", "50", nvim }))
    local ready = vim.wait(5000, function()
      return (tmux.run({ "capture-pane", "-p", "-t", "ui:" }) or ""):find("# a", 1, true) ~= nil
    end, 50)
    local ok, err = pcall(function()
      assert(ready, "nvim did not render the buffer")
      fn()
    end)
    tmux.run({ "kill-server" })
    tmux.socket = nil
    assert(ok, err)
  end)
end

local function type(...)
  for _, key in ipairs({ ... }) do
    assert(tmux.run({ "send-keys", "-t", "ui:", key }))
    vim.wait(150)
  end
end

local function panes(session)
  local out = tmux.run({ "list-panes", "-s", "-t", session, "-F", "#{pane_id}" })
  return out and vim.split(out, "\n") or {}
end

local function screen()
  return tmux.run({ "capture-pane", "-p", "-t", "ui:" }) or ""
end

local function wait(fn)
  return vim.wait(3000, fn, 50)
end

local function write()
  type(":w", "Enter")
end

-- The buffer: 1 "# a", 2 its window, 3-4 its panes, 5 "# ui", 6 its window,
-- 7 the nvim pane.

with_nvim("buffer: dd and p move a pane to another session", function()
  local before = panes("a")
  type("3G", "dd", "G", "p")
  write()
  wait(function()
    return #panes("ui") == 2
  end)
  eq(true, vim.tbl_contains(panes("ui"), before[1]))
  eq({ before[2] }, panes("a"))
end)

with_nvim("buffer: a session line above the panes moves them to a new session", function()
  local before = panes("a")
  type("3G", "O", "# x", "Escape")
  write()
  wait(function()
    return #panes("x") == 2
  end)
  local after = panes("x")
  table.sort(before)
  table.sort(after)
  eq(before, after)
end)

with_nvim("buffer: editing the window line renames the window", function()
  local function name()
    return tmux.run({ "display-message", "-p", "-t", "a:0", "#{window_name}" })
  end
  type("2G", "$", "ciw", "renamed", "Escape")
  write()
  wait(function()
    return name() == "renamed"
  end)
  eq("renamed", name())
end)

with_nvim("buffer: o on a pane line adds a pane that runs the command", function()
  type("3G", "o", "echo $((40 + 2))-marker", "Escape")
  write()
  wait(function()
    return #panes("a") == 3
  end)
  eq(3, #panes("a"))
  local found = wait(function()
    for _, id in ipairs(panes("a")) do
      if (tmux.run({ "capture-pane", "-p", "-t", id }) or ""):find("42%-marker") then
        return true
      end
    end
  end)
  eq(true, found)
end)

with_nvim("buffer: the preview shows the plan", function()
  type("3G", "O", "# x", "Escape")
  eq(true, wait(function()
    return screen():find("new session x:", 1, true) ~= nil
  end))
  type("j", "dd")
  eq(true, wait(function()
    return screen():find("1 pane killed", 1, true) ~= nil
  end))
end)
