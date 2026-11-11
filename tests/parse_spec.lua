local h = dofile("tests/helpers.lua")
local view = require("tmux-oil.view")
local parse = require("tmux-oil.parse")

local function brief(rows)
  return vim.tbl_map(function(r)
    return { r.id, r.session, r.index, r.name }
  end, rows)
end

test("parse: render round trip", function()
  local state = h.state({ { "a", 1, "editor", "nvim" }, { "a", 1, "editor" }, { "b", 3, "logs", "k9s" } })
  local lines = view.render(state, h.config)
  eq("# a", lines[1])
  eq("  1: editor", lines[2])
  eq({
    { "%1", "a", 1, "editor" },
    { "%2", "a", 1, "editor" },
    { "%3", "b", 3, "logs" },
  }, brief(parse.parse(lines)))
end)

test("parse: blank lines are skipped", function()
  local rows = parse.parse({ "", "# a", "   ", "  1: w", "", "    %1 zsh" })
  eq({ { "%1", "a", 1, "w" } }, brief(rows))
  eq(6, rows[1].lnum)
end)

test("parse: indentation does not matter", function()
  local want = brief(parse.parse({ "# a", "  1: w", "    %1 zsh", "    htop" }))
  eq(want, brief(parse.parse({ "# a", "1: w", "%1 zsh", "htop" })))
  local rows = parse.parse({ "    # a", "        1: w", "  %1 zsh", "          htop" })
  eq(want, brief(rows))
  eq("htop", rows[2].command)
end)

test("parse: a new line is a command and keeps its pipes", function()
  local rows = parse.parse({ "# a", "  1: w", "    tail -f x | grep ERROR" })
  eq(nil, rows[1].id)
  eq("a:1", rows[1].target)
  eq("tail -f x | grep ERROR", rows[1].command)
end)

test("parse: a window line without index is a new window", function()
  local rows = parse.parse({ "# a", "  : logs", "    %1 zsh", "  : other", "    %2 zsh" })
  eq({ { "%1", "a", nil, "logs" }, { "%2", "a", nil, "other" } }, brief(rows))
  eq({ 2, 4 }, { rows[1].window_lnum, rows[2].window_lnum })
  eq("a:", rows[1].target)
end)

test("parse: a pane right under a session has no window", function()
  local rows = parse.parse({ "# a", "  1: w", "# x", "    %1 zsh" })
  eq({ { "%1", "x", nil, "" } }, brief(rows))
  eq(nil, rows[1].window_lnum)
end)

test("parse: two ids in one line is an error", function()
  local rows, err = parse.parse({ "# a", "  1: w", "    %1 zsh %2 zsh" })
  eq(nil, rows)
  eq(true, err:find("line 3") ~= nil)
end)

test("parse: a pane above the first session is an error", function()
  local rows, err = parse.parse({ "  1: w", "    %1 zsh", "# a" })
  eq(nil, rows)
  eq(true, err:find("line 2") ~= nil)
end)
