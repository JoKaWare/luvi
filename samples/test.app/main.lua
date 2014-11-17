local env = require('env')
local uv = require('uv')
local bundle = require('luvi').bundle
-- Register the utils lib as a module
bundle.register("utils", "utils.lua")

local utils = require('utils')
local dump = require('utils').dump

local stdout
if uv.guess_handle(1) == "TTY" then
  stdout = uv.new_tty(1, false)
  utils.init(true)
  print("STDOUT is TTY")
else
  stdout = uv.new_pipe(false)
  uv.pipe_open(stdout, 1)
  utils.init(false)
  print("STDOUT is PIPE")
end


local function deepEqual(expected, actual, path)
  if expected == actual then
    return true
  end
  local prefix = path and (path .. ": ") or ""
  local expectedType = type(expected)
  local actualType = type(actual)
  if expectedType ~= actualType then
    return false, prefix .. "Expected type " .. expectedType .. " but found " .. actualType
  end
  if expectedType ~= "table" then
    return false, prefix .. "Expected " .. tostring(expected) .. " but found " .. tostring(actual)
  end
  local expectedLength = #expected
  local actualLength = #actual
  for key in pairs(expected) do
    if actual[key] == nil then
      return false, prefix .. "Missing table key " .. key
    end
    local newPath = path and (path .. '.' .. key) or key
    local same, message = deepEqual(expected[key], actual[key], newPath)
    if not same then
      return same, message
    end
  end
  if expectedLength ~= actualLength then
    return false, prefix .. "Expected table length " .. expectedLength .. " but found " .. actualLength
  end
  for key in pairs(actual) do
    if expected[key] == nil then
      return false, prefix .. "Unexpected table key " .. key
    end
  end
  return true
end

_G.p = function (...)
  local n = select('#', ...)
  local arguments = { ... }

  for i = 1, n do
    arguments[i] = dump(arguments[i])
  end

  local toWrite = table.concat(arguments, "\t") .. "\n"
  uv.write(stdout, toWrite);
end

local env = setmetatable({}, {
  __pairs = function (table)
    local keys = env.keys(true)
    local index = 0
    return function ()
      index = index + 1
      local name = keys[index]
      if name then
        return name, table[name]
      end
    end
  end,
  __index = function (_, name)
    local value = env.get(name)
    return value
  end,
  __newindex = function (_, name, value)
    if value then
      env.set(name, value)
    else
      env.unset(name)
    end
  end
})

-- Make sure unicode can round-trip in unicode environment variable names and values.
local r1 = "На берегу пустынных волн"
local r2 = "Стоял он, дум великих полн"
env[r1] = r2
assert(env[r1] == r2)
p(env)
p{
  args=args,
  bundle=bundle
}
p{
  [""] = bundle.stat(""),
  ["add"] = bundle.stat("add"),
  ["main.lua"] = bundle.stat("main.lua"),
  ["fake"] = bundle.stat("fake"),
}
p(bundle.readfile("greetings.txt"))


print("Testing bundle.stat")
local rootStat = bundle.stat("")
assert(rootStat.type == "directory")
local addStat = bundle.stat("add")
assert(addStat.type == "directory")
local mainStat = bundle.stat("main.lua")
assert(mainStat.type == "file")
assert(mainStat.size > 3000)
local tests = {
  "", rootStat,
  "/", rootStat,
  "/a/../", rootStat,
  "add", addStat,
  "add/", addStat,
  "/add/", addStat,
  "foo/../add/", addStat,
  "main.lua", mainStat,
  "/main.lua", mainStat,
}
for i = 1, #tests, 2 do
  local path = tests[i]
  local expected = tests[i + 1]
  local actual = bundle.stat(path)
  p(path, actual)
  assert(deepEqual(expected, actual), "ERROR: stat(" .. path .. ")")
end

print("Testing bundle.readdir")
local rootTree = { "add", "greetings.txt", "main.lua", "utils.lua" }
local addTree = { "a.lua", "b.lua", "init.lua" }
tests = {
  "", rootTree,
  "/", rootTree,
  "/a/../", rootTree,
  "add", addTree,
  "add/", addTree,
  "/add/", addTree,
  "foo/../add/", addTree,
}
table.sort(rootTree)
table.sort(addTree)
for i = 1, #tests, 2 do
  local path = tests[i]
  local expected = tests[i + 1]
  local actual = bundle.readdir(path)
  table.sort(actual)
  p(path, actual)
  assert(deepEqual(expected, actual), "ERROR: readdir(" .. path .. ")")
end

print("Testing for lua 5.2 extensions")
local thread, ismain = coroutine.running()
p(thread, ismain)
assert(thread)
assert(ismain)


print("All tests pass!\n")
