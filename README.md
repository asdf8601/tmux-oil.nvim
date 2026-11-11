# tmux-oil.nvim

Edit tmux sessions, windows and panes as a Neovim buffer, in the style of
[oil.nvim](https://github.com/stevearc/oil.nvim). The buffer is a tree of
sessions, windows and panes; edit it and `:w` applies the changes to tmux.

```
# work
  1: shell
    zsh     Review notes  ~/projects
  3: editor
    claude  api-server    ~/projects
    nvim                  …/api-server
# dotfiles
  1: main
    nvim                  ~/dotfiles
```

Requires Neovim >= 0.10 and tmux. No other dependencies.

## Install

With lazy.nvim:

```lua
{ "asdf8601/tmux-oil.nvim", opts = {} }
```

## Editing

Lines are told apart by their content; indentation is cosmetic.

- `# name` is a session.
- `N: name` is a window of the session above.
- A line that starts with a hidden pane id is an existing pane of the window
  above. Its text (command, title, cwd) is only a label; edits to it are
  ignored.
- Any other line is a new pane, and its whole text is the command to run.

| Edit | Result |
|---|---|
| Move a pane line under another window (`dd` + `p`) | move the pane there, other sessions included |
| Move a window block under another `# session` | move the window to that session |
| Delete a pane line | kill the pane |
| Edit the text after `N:` | rename the window |
| Add a line under a window, e.g. `k9s` | new pane that runs that text in its shell |
| Copy a pane line with `yyp` | new shell next to the original, same cwd |
| Add a window line without a number (`: logs`) with lines under it | new window |
| Add a `# name` line with lines under it | new session |

Folds follow the indentation, so `zc` on a window and then `dd` takes the
whole block. A window block pasted into a session that already has that index
puts its panes into the existing window; drop the number to get a new window.
Deleting only a window line does not kill its panes, they join the window
above.

Changes that kill panes or destroy windows ask for confirmation first. When
an edit moves the last panes out of the session your client is attached to,
the client follows the last moved pane and the empty session goes away. An
edit that would empty that session only by killing panes is refused.

## Keys

- `<CR>` switch to the pane under the cursor, or to the session on a
  `# session` line
- `R` reload from tmux, discarding edits

While you edit, each line shows what `:w` will do with it
(`→ new session work:`, `+ new pane`, `✎ rename window`), and the first line
sums up what the buffer cannot show, such as killed panes.

## Popup

```tmux
bind S display-popup -E -w 80% -h 80% "nvim -c 'lua require(\"tmux-oil\").open({ close_on_switch = true })'"
```

## Options

```lua
require("tmux-oil").setup({
  max_width = { title = 30, cwd = 25 },
  confirm = "destructive", -- "always" | "destructive" | "never"
  close_on_switch = false,
  command_alias = {}, -- { ["^%d+%.%d+%.%d+$"] = "claude" }
  socket = nil, -- tmux -L socket
})
```

## Tests

```sh
make test
```

Integration tests run against an isolated server (`tmux -L tmux-oil-test`).
