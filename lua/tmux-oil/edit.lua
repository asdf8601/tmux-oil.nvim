local parse = require("tmux-oil.parse")
local diff = require("tmux-oil.diff")

local M = {}

local preview_ns = vim.api.nvim_create_namespace("tmux-oil-preview")

-- Shows next to each line what :w would do with it.
function M.preview(buf, state, ctx)
  vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
  if not state then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local function note(lnum, text, group)
    lnum = math.min(math.max(lnum, 1), count)
    vim.api.nvim_buf_set_extmark(buf, preview_ns, lnum - 1, 0, { virt_text = { { "  " .. text, group } }, virt_text_pos = "eol" })
  end
  local function fail(err)
    note(tonumber(err:match("^line (%d+)")) or 1, "✗ " .. err, "DiagnosticError")
  end

  local rows, err = parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if not rows then
    return fail(err)
  end
  local plan
  plan, err = diff.compute(state, rows, ctx)
  if not plan then
    return fail(err)
  end
  for lnum, n in pairs(plan.notes) do
    note(lnum, n[1], n[2])
  end
  local summary = diff.summary(plan)
  if summary ~= "" then
    note(1, summary, "DiagnosticError")
  end
end

function M.attach(buf, get)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      local state, ctx = get()
      M.preview(buf, state, ctx)
    end,
  })
end

return M
