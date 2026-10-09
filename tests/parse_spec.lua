local h = dofile("tests/helpers.lua")
local view = require("tmux-oil.view")
local parse = require("tmux-oil.parse")

local cols = h.config.columns

local function brief(rows)
  return vim.tbl_map(function(r)
    return { r.id, r.session, r.index, r.name, r.command }
  end, rows)
end

test("parse: render round trip", function()
  local state = h.state({ { "a", 1, "editor", "nvim" }, { "a", 1, "editor" }, { "b", 3, "logs", "k9s" } })
  local lines = view.render(state, h.config)
  eq({
    { "%1", "a", 1, "editor", "nvim" },
    { "%2", "a", 1, "", "zsh" },
    { "%3", "b", 3, "logs", "k9s" },
  }, brief(parse.parse(lines, cols)))
end)

test("parse: header and blank lines are skipped", function()
  local rows = parse.parse({ "TARGET | NAME | TITLE | CWD | COMMAND", "", "   ", "%1 a:1 | | | | zsh" }, cols)
  eq({ { "%1", "a", 1, "", "zsh" } }, brief(rows))
end)

test("parse: the last column keeps its pipes", function()
  local rows = parse.parse({ "a:1 | | | | tail -f x | grep ERROR" }, cols)
  eq("tail -f x | grep ERROR", rows[1].command)
end)

test("parse: missing trailing columns are empty", function()
  local rows = parse.parse({ "a: | logs" }, cols)
  eq({ { nil, "a", nil, "logs", "" } }, brief(rows))
end)

test("parse: two ids in one line is an error", function()
  local rows, err = parse.parse({ "%1 a:1 | | | | zsh %2 a:1 | | | | zsh" }, cols)
  eq(nil, rows)
  eq(true, err:find("line 1") ~= nil)
end)

test("parse: invalid target is an error", function()
  local rows, err = parse.parse({ "%1 nocolon | | | | zsh" }, cols)
  eq(nil, rows)
  eq(true, err:find("invalid target") ~= nil)
end)

test("view: pipes in informative columns are escaped", function()
  local state = h.state({ { "a", 1, "w" } })
  state.panes[1].title = "x|y"
  local lines = view.render(state, h.config)
  eq("x¦y", parse.parse(lines, cols)[1].title)
end)
