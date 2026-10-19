-- usage: lua54 check_lua.lua <dir>... : reports files that fail to compile
local bad = 0
for _, dir in ipairs(arg) do
  local p = io.popen('ls "' .. dir .. '"')
  for f in p:lines() do
    if f:match("%.lua$") then
      local fn, err = loadfile(dir .. "/" .. f)
      if not fn then bad = bad + 1; print(err) end
    end
  end
end
print("syntax errors:", bad)
