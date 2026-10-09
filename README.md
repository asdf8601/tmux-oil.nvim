# tmux-oil.nvim

Edit tmux sessions, windows and panes as a Neovim buffer, in the style of
[oil.nvim](https://github.com/stevearc/oil.nvim). Each line is a pane; edit
the buffer and `:w` applies the changes to tmux.

```
TARGET   | NAME   | TITLE         | CWD          | COMMAND
work:1   | shell  | Review notes  | ~/projects   | zsh
work:3   | editor | api-server    | ~/projects   | claude
work:3   |        |               | …/api-server | nvim
```

Requires Neovim >= 0.10 and tmux. No other dependencies.

## Install

With lazy.nvim:

```lua
{ "asdf8601/tmux-oil.nvim", opts = {} }
```

## Editing

Every line starts with a hidden pane id. `TARGET` is `session:index`.

| Edit | Result |
|---|---|
| Change the target to an existing window | move the pane there |
| Change the target to an unknown index, or `session:` | move it to a new window |
| Change the target to an unknown session | move it to a new session |
| Edit `NAME` on a window's first line | rename the window |
| Delete a line | kill the pane |
| Add a line, e.g. `work: \| logs \| \| \| k9s` | create the pane and run `COMMAND` in its shell |
| Copy a line with `yyp` | new shell next to the original, same cwd |

Lines with the same new target form one window. `TITLE` and `CWD` are read
only. `COMMAND` is the last column, so it may contain `|`.

Changes that kill panes or destroy windows ask for confirmation first. When
an edit moves the last panes out of the session your client is attached to,
the client follows the last moved pane and the empty session goes away. An
edit that would empty that session only by killing panes is refused.

## Keys

- `<CR>` switch to the pane under the cursor
- `R` reload from tmux, discarding edits
- `<Tab>` / `<S-Tab>` next or previous cell, in normal and insert mode
- `ic` text object for the cell under the cursor: `cic` changes just that cell
- `o` / `O` new pane line in the current window, cursor in `COMMAND`

Columns realign when you leave insert mode; one `u` undoes the edit and the
realignment. While you edit, each line shows what `:w` will do with it
(`→ new session work:`, `+ new pane`, `✎ rename window`), and the first line
sums up what the buffer cannot show, such as killed panes.

## Popup

```tmux
bind S display-popup -E -w 80% -h 80% "nvim -c 'lua require(\"tmux-oil\").open({ close_on_switch = true })'"
```

## Options

```lua
require("tmux-oil").setup({
  columns = { "target", "name", "title", "cwd", "command" }, -- target required, command last
  max_width = { title = 30, cwd = 25 },
  confirm = "destructive", -- "always" | "destructive" | "never"
  close_on_switch = false,
  command_alias = {}, -- { ["^%d+%.%d+%.%d+$"] = "claude" }
  header = true,
  socket = nil, -- tmux -L socket
})
```

## Tests

```sh
make test
```

Integration tests run against an isolated server (`tmux -L tmux-oil-test`).
