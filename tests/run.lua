vim.opt.rtp:prepend(vim.fn.getcwd())

local tests = {}

_G.test = function(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

_G.eq = function(want, got)
  if not vim.deep_equal(want, got) then
    error(("expected %s\ngot %s"):format(vim.inspect(want), vim.inspect(got)), 2)
  end
end

for _, file in ipairs(vim.fn.glob("tests/*_spec.lua", false, true)) do
  dofile(file)
end

local failed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  print((ok and "ok   " or "FAIL ") .. t.name)
  if not ok then
    failed = failed + 1
    print("     " .. tostring(err):gsub("\n", "\n     "))
  end
end
print(("%d tests, %d failed"):format(#tests, failed))
os.exit(failed == 0 and 0 or 1)
