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
      return (tmux.run({ "capture-pane", "-p", "-t", "ui:" }) or ""):find("TARGET") ~= nil
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

local function write_and_wait(want_session)
  type(":w", "Enter")
  vim.wait(3000, function()
    return #panes(want_session) > 0
  end, 50)
end

with_nvim("buffer: editing from the start of the line keeps the pane id", function()
  local before = panes("a")
  type("j", "0", "cW", "x:", "Escape")
  write_and_wait("x")
  eq({ before[1] }, panes("x"))
  eq({ before[2] }, panes("a"))
end)

with_nvim("buffer: visual block over the target column moves every pane", function()
  local before = panes("a")
  type("j", "0", "C-v", "j", "E", "c", "x:", "Escape")
  write_and_wait("x")
  local after = panes("x")
  table.sort(before)
  table.sort(after)
  eq(before, after)
end)

local function screen()
  return tmux.run({ "capture-pane", "-p", "-t", "ui:" }) or ""
end

with_nvim("buffer: cic on the target cell moves the pane", function()
  local before = panes("a")
  type("j", "cic", "x:", "Escape")
  write_and_wait("x")
  eq({ before[1] }, panes("x"))
end)

with_nvim("buffer: Tab reaches the name cell", function()
  type("j", "Tab", "cic", "renamed", "Escape", ":w", "Enter")
  vim.wait(1000, function()
    return tmux.run({ "display-message", "-p", "-t", "a:0", "#{window_name}" }) == "renamed"
  end, 50)
  eq("renamed", tmux.run({ "display-message", "-p", "-t", "a:0", "#{window_name}" }))
end)

with_nvim("buffer: o opens a line in the same window ready for a command", function()
  type("j", "o", "echo $((40 + 2))-marker", "Escape", ":w", "Enter")
  vim.wait(3000, function()
    return #panes("a") == 3
  end, 50)
  eq(3, #panes("a"))
  local found = vim.wait(3000, function()
    for _, id in ipairs(panes("a")) do
      if (tmux.run({ "capture-pane", "-p", "-t", id }) or ""):find("42%-marker") then
        return true
      end
    end
  end, 50)
  eq(true, found)
end)

with_nvim("buffer: leaving insert realigns and the preview shows the plan", function()
  type("j", "cic", "brand-new-session:", "Escape")
  local lines = vim.split(screen(), "\n")
  local header, edited = lines[1], lines[2]
  eq(header:find("|", 1, true), edited:find("|", 1, true))
  eq(true, edited:find("→ new session brand%-new%-session:") ~= nil)
  type("j", "dd")
  eq(true, screen():find("1 pane killed") ~= nil)
end)

with_nvim("buffer: one undo reverts the edit and the realignment", function()
  local original = vim.split(screen(), "\n")[2]
  type("j", "cic", "brand-new-session:", "Escape", "u")
  eq(original, vim.split(screen(), "\n")[2])
end)
