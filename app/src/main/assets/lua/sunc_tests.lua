-- sunc_tests.lua : behaviour tests in the spirit of sUNC
-- One test per UNC/sUNC function. A test receives the function under test.
-- Status values reported to the app: pass | warn (aliases missing) | fail | missing

local H = __host
local G = _G
local X = H.X
local rawtype = H.rawtype

local tests = {}
local function T(name, category, fn)
  tests[#tests + 1] = { name = name, category = category, fn = fn }
end

local function expect(cond, msg)
  if not cond then error(msg or "assertion failed", 0) end
end

local function resolve(path)
  local cur = G
  for part in string.gmatch(path, "[^.]+") do
    if rawtype(cur) ~= "table" then return nil end
    cur = cur[part]
    if cur == nil then return nil end
  end
  return cur
end

local function R(name)
  local f = resolve(name)
  if f == nil then error("needs '" .. name .. "' which is missing", 0) end
  return f
end

local function contains(list, value)
  for _, v in pairs(list) do
    if v == value then return true end
  end
  return false
end

local TMP = {}
local function tmp(class, parent)
  local i = Instance.new(class)
  i.Name = "__sunc" .. (#TMP + 1)
  TMP[#TMP + 1] = i
  if parent ~= false then i.Parent = parent or workspace end
  return i
end

local DIR = "__sunc_test"

------------------------------------------------------------------------
-- Cache
------------------------------------------------------------------------
T("cache.invalidate", "Cache", function(f)
  local part = tmp("Part")
  expect(workspace:FindFirstChild(part.Name) == part, "setup failed")
  f(part)
  local after = workspace:FindFirstChild(part.Name)
  expect(after ~= nil and after ~= part, "the old reference is still the cached one")
  expect(after.Name == part.Name, "new reference does not point at the same instance")
end)

T("cache.iscached", "Cache", function(f)
  local part = tmp("Part")
  expect(f(part) == true, "fresh instance should be cached")
  R("cache.invalidate")(part)
  expect(f(part) == false, "invalidated instance should not be cached")
end)

T("cache.replace", "Cache", function(f)
  local a = tmp("Part")
  local b = tmp("Part", false)
  local name = a.Name
  f(a, b)
  expect(a ~= b, "references became equal")
  expect(workspace:FindFirstChild(name) == b, "replacement was not applied")
end)

T("cloneref", "Cache", function(f)
  local part = tmp("Part")
  local c = f(part)
  expect(c ~= part, "clone should be a different reference")
  expect(c.Name == part.Name, "clone does not mirror the instance")
  c.Name = "__sunc_renamed"
  expect(part.Name == "__sunc_renamed", "clone is not linked to the original")
end)

T("compareinstances", "Cache", function(f)
  local part = tmp("Part")
  local other = tmp("Part")
  expect(f(part, R("cloneref")(part)) == true, "clone should compare equal")
  expect(f(part, other) == false, "different instances compared equal")
end)

------------------------------------------------------------------------
-- Closures
------------------------------------------------------------------------
T("checkcaller", "Closures", function(f)
  expect(f() == true, "should be true when called from the executor")
end)

T("clonefunction", "Closures", function(f)
  local function test() return "success" end
  local copy = f(test)
  expect(test ~= copy, "clone is the same function")
  expect(copy() == "success", "clone does not behave like the original")
end)

T("getcallingscript", "Closures", function(f)
  local s = f()
  expect(s == nil or typeof(s) == "Instance", "should return nil or an Instance")
end)

T("getscriptclosure", "Closures", function(f)
  local mod = tmp("ModuleScript")
  mod.Source = "return { value = 5 }"
  local fn = f(mod)
  expect(type(fn) == "function", "should return a function")
  expect(fn().value == 5, "closure does not return the module value")
end)

T("hookfunction", "Closures", function(f)
  local function test() return false end
  local ref = f(test, function() return true end)
  expect(test() == true, "the function was not hooked")
  expect(ref() == false, "the original function was not returned")
end)

T("iscclosure", "Closures", function(f)
  expect(f(print) == true, "print should be a C closure")
  expect(f(function() end) == false, "a Lua function is not a C closure")
end)

T("islclosure", "Closures", function(f)
  expect(f(print) == false, "print is not a Lua closure")
  expect(f(function() end) == true, "a Lua function is a Lua closure")
end)

T("isexecutorclosure", "Closures", function(f)
  expect(f(print) == false, "print is not an executor closure")
  expect(f(function() end) == true, "script functions are executor closures")
  expect(f(R("newcclosure")(function() end)) == true, "newcclosure results are executor closures")
end)

T("loadstring", "Closures", function(f)
  local fn = f("return 5")
  expect(type(fn) == "function" and fn() == 5, "did not compile the chunk")
  local bad, err = f("this is not lua !!")
  expect(bad == nil and type(err) == "string", "should return nil + error for bad code")
end)

T("newcclosure", "Closures", function(f)
  local c = f(function() return "x" end)
  expect(c() == "x", "wrapper does not call through")
  expect(R("iscclosure")(c) == true, "wrapper should be a C closure")
end)

T("getfunctionhash", "Closures", function(f)
  local function a() return 1 end
  local function b() return 2 end
  local h = f(a)
  expect(type(h) == "string" and #h > 0, "should return a hash string")
  expect(f(a) == h, "hash is not stable")
  expect(f(b) ~= h, "different functions share a hash")
end)

T("restorefunction", "Closures", function(f)
  local function test() return false end
  R("hookfunction")(test, function() return true end)
  expect(test() == true, "hook did not apply")
  f(test)
  expect(test() == false, "function was not restored")
end)

------------------------------------------------------------------------
-- Console
------------------------------------------------------------------------
T("rconsolecreate", "Console", function(f)
  f()
  R("rconsoledestroy")()
end)

T("rconsoleclear", "Console", function(f)
  R("rconsolecreate")()
  f()
  R("rconsoledestroy")()
end)

T("rconsoledestroy", "Console", function(f)
  R("rconsolecreate")()
  f()
end)

T("rconsoleprint", "Console", function(f)
  R("rconsolecreate")()
  f("sUNC test line\n")
  R("rconsoledestroy")()
end)

T("rconsolesettitle", "Console", function(f)
  R("rconsolecreate")()
  f("sUNC")
  R("rconsoledestroy")()
end)

T("rconsoleinput", "Console", function(f)
  -- can't be driven automatically (it waits for the user); only check it is callable
  expect(type(f) == "function", "not a function")
end)

------------------------------------------------------------------------
-- Crypt / encoding
------------------------------------------------------------------------
T("crypt.base64encode", "Crypt", function(f)
  expect(f("test") == "dGVzdA==", "wrong base64 output")
end)

T("crypt.base64decode", "Crypt", function(f)
  expect(f("dGVzdA==") == "test", "wrong base64 decode")
end)

T("crypt.generatekey", "Crypt", function(f)
  local k = f()
  expect(type(k) == "string", "key should be a string")
  expect(#R("crypt.base64decode")(k) == 32, "key should be 32 bytes")
end)

T("crypt.generatebytes", "Crypt", function(f)
  local b = f(16)
  expect(#R("crypt.base64decode")(b) == 16, "should return 16 random bytes (base64)")
  expect(f(16) ~= b, "bytes are not random")
end)

T("crypt.encrypt", "Crypt", function(f)
  local key = R("crypt.generatekey")()
  local dec = R("crypt.decrypt")
  for _, mode in ipairs({ "CBC", "ECB", "CTR", "CFB", "GCM" }) do
    local enc, iv = f("hello world", key, nil, mode)
    expect(enc ~= "hello world", mode .. ": data was not encrypted")
    expect(dec(enc, key, iv, mode) == "hello world", mode .. ": round trip failed")
  end
end)

T("crypt.decrypt", "Crypt", function(f)
  local key = R("crypt.generatekey")()
  local enc, iv = R("crypt.encrypt")("secret data", key, nil, "CBC")
  expect(f(enc, key, iv, "CBC") == "secret data", "decryption failed")
end)

T("crypt.hash", "Crypt", function(f)
  expect(f("test", "sha256") == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "sha256 mismatch")
  expect(f("test", "md5") == "098f6bcd4621d373cade4e832627b4f6", "md5 mismatch")
  expect(f("test", "sha1") == "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3", "sha1 mismatch")
  expect(#f("test", "sha512") == 128, "sha512 length mismatch")
end)

T("base64encode", "Crypt", function(f)
  expect(f("Hello") == "SGVsbG8=", "wrong output")
end)

T("base64decode", "Crypt", function(f)
  expect(f("SGVsbG8=") == "Hello", "wrong output")
end)

T("lz4compress", "Crypt", function(f)
  local data = string.rep("abcd", 200)
  local c = f(data)
  expect(type(c) == "string" and #c < #data, "data was not compressed")
  expect(R("lz4decompress")(c, #data) == data, "round trip failed")
end)

T("lz4decompress", "Crypt", function(f)
  local data = string.rep("roblox ", 150) .. "end"
  local c = R("lz4compress")(data)
  expect(f(c, #data) == data, "decompressed data differs")
end)

------------------------------------------------------------------------
-- Debug
------------------------------------------------------------------------
T("debug.getconstants", "Debug", function(f)
  local function test()
    local a = "uniqueconst_a"
    return a .. "uniqueconst_b", 98765
  end
  local k = f(test)
  expect(type(k) == "table", "should return a table")
  expect(contains(k, "uniqueconst_a") and contains(k, "uniqueconst_b") and contains(k, 98765), "constants missing")
end)

T("debug.getconstant", "Debug", function(f)
  local function test() return "only_constant" end
  expect(f(test, 1) == "only_constant", "wrong constant")
  expect(not pcall(f, test, 99), "out of range index should error")
end)

T("debug.setconstant", "Debug", function(f)
  local function test() return "old_value" end
  f(test, 1, "new_value")
  expect(test() == "new_value", "constant was not changed")
end)

T("debug.getinfo", "Debug", function(f)
  local info = f(print)
  expect(type(info) == "table", "should return a table")
  local function test(a, b) return a + b end
  local info2 = f(test)
  expect(type(info2) == "table" and info2.func == test, "func field missing")
end)

T("debug.getproto", "Debug", function(f)
  local function outer()
    local function inner() return 1 end
    return inner
  end
  local p = f(outer, 1)
  expect(type(p) == "function", "should return the inner function")
  expect(not pcall(f, outer, 5), "out of range proto should error")
end)

T("debug.getprotos", "Debug", function(f)
  local function outer()
    local function a() end
    local function b() end
    return a, b
  end
  expect(#f(outer) == 2, "should return both inner functions")
end)

T("debug.getstack", "Debug", function(f)
  local function test()
    local marker = "stack_marker_value"
    local s = f(1)
    return s
  end
  local s = test()
  expect(type(s) == "table", "should return a table")
  expect(contains(s, "stack_marker_value"), "stack value not found")
  local function second()
    local first, second_local = "a", "b"
    return f(1, 2)
  end
  expect(second() == "b", "index access returned the wrong value")
end)

T("debug.setstack", "Debug", function(f)
  local function test()
    local target = "before"
    f(1, 1, "after")
    return target
  end
  expect(test() == "after", "stack value was not changed")
end)

T("debug.getupvalues", "Debug", function(f)
  local a, b = "up_one", "up_two"
  local function test() return a .. b end
  local ups = f(test)
  expect(type(ups) == "table" and #ups == 2, "should return 2 upvalues")
  expect(ups[1] == "up_one" and ups[2] == "up_two", "wrong upvalue order/values")
end)

T("debug.getupvalue", "Debug", function(f)
  local a = "upvalue_value"
  local function test() return a end
  expect(f(test, 1) == "upvalue_value", "wrong upvalue")
  expect(not pcall(f, test, 9), "out of range should error")
end)

T("debug.setupvalue", "Debug", function(f)
  local a = "old"
  local function test() return a end
  f(test, 1, "new")
  expect(test() == "new", "upvalue was not changed")
end)

------------------------------------------------------------------------
-- Filesystem
------------------------------------------------------------------------
T("writefile", "Filesystem", function(f)
  f(DIR .. "/w.txt", "hello")
  expect(R("readfile")(DIR .. "/w.txt") == "hello", "content mismatch")
  f(DIR .. "/w.txt", "bye")
  expect(R("readfile")(DIR .. "/w.txt") == "bye", "file was not overwritten")
end)

T("readfile", "Filesystem", function(f)
  R("writefile")(DIR .. "/r.txt", "read me")
  expect(f(DIR .. "/r.txt") == "read me", "content mismatch")
  expect(not pcall(f, DIR .. "/does_not_exist.txt"), "missing file should error")
end)

T("appendfile", "Filesystem", function(f)
  R("writefile")(DIR .. "/a.txt", "a")
  f(DIR .. "/a.txt", "b")
  expect(R("readfile")(DIR .. "/a.txt") == "ab", "append failed")
end)

T("makefolder", "Filesystem", function(f)
  f(DIR .. "/folder")
  expect(R("isfolder")(DIR .. "/folder") == true, "folder was not created")
end)

T("isfolder", "Filesystem", function(f)
  R("makefolder")(DIR .. "/isf")
  expect(f(DIR .. "/isf") == true, "should be true for a folder")
  expect(f(DIR .. "/nope") == false, "should be false for a missing folder")
end)

T("isfile", "Filesystem", function(f)
  R("writefile")(DIR .. "/isfile.txt", "x")
  expect(f(DIR .. "/isfile.txt") == true, "should be true for a file")
  expect(f(DIR .. "/nope.txt") == false, "should be false for a missing file")
  expect(f(DIR) == false, "a folder is not a file")
end)

T("listfiles", "Filesystem", function(f)
  R("makefolder")(DIR .. "/list")
  R("writefile")(DIR .. "/list/one.txt", "1")
  R("writefile")(DIR .. "/list/two.txt", "2")
  local files = f(DIR .. "/list")
  expect(type(files) == "table" and #files == 2, "should list 2 entries")
  expect(contains(files, DIR .. "/list/one.txt"), "entry missing")
end)

T("delfile", "Filesystem", function(f)
  R("writefile")(DIR .. "/del.txt", "x")
  f(DIR .. "/del.txt")
  expect(R("isfile")(DIR .. "/del.txt") == false, "file still exists")
end)

T("delfolder", "Filesystem", function(f)
  R("makefolder")(DIR .. "/delme")
  R("writefile")(DIR .. "/delme/x.txt", "x")
  f(DIR .. "/delme")
  expect(R("isfolder")(DIR .. "/delme") == false, "folder still exists")
end)

T("loadfile", "Filesystem", function(f)
  R("writefile")(DIR .. "/load.lua", "return 1 + 1")
  local fn = f(DIR .. "/load.lua")
  expect(type(fn) == "function" and fn() == 2, "did not compile the file")
end)

T("dofile", "Filesystem", function(f)
  R("writefile")(DIR .. "/do.lua", "return 42")
  expect(f(DIR .. "/do.lua") == 42, "did not run the file")
end)

T("getcustomasset", "Filesystem", function(f)
  R("writefile")(DIR .. "/asset.txt", "asset")
  local a = f(DIR .. "/asset.txt")
  expect(type(a) == "string" and a:find("rbxasset://", 1, true) == 1, "should return an rbxasset:// url")
  expect(not pcall(f, DIR .. "/missing.png"), "missing file should error")
end)

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------
T("isrbxactive", "Input", function(f)
  expect(type(f()) == "boolean", "should return a boolean")
end)
T("mouse1click", "Input", function(f) f() end)
T("mouse1press", "Input", function(f) f(); R("mouse1release")() end)
T("mouse1release", "Input", function(f) R("mouse1press")(); f() end)
T("mouse2click", "Input", function(f) f() end)
T("mouse2press", "Input", function(f) f(); R("mouse2release")() end)
T("mouse2release", "Input", function(f) R("mouse2press")(); f() end)
T("mousemoveabs", "Input", function(f)
  f(120, 240)
  local x, y = H.cursor()
  expect(x == 120 and y == 240, "cursor did not move")
end)
T("mousemoverel", "Input", function(f)
  R("mousemoveabs")(100, 100)
  f(15, -10)
  local x, y = H.cursor()
  expect(x == 115 and y == 90, "cursor did not move relatively")
end)
T("mousescroll", "Input", function(f) f(10) end)

------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------
T("fireclickdetector", "Instances", function(f)
  local cd = Instance.new("ClickDetector", tmp("Part"))
  local fired = false
  cd.MouseClick:Connect(function() fired = true end)
  f(cd)
  expect(fired, "MouseClick did not fire")
  expect(not pcall(f, workspace), "should reject non-ClickDetectors")
end)

T("getcallbackvalue", "Instances", function(f)
  local bf = Instance.new("BindableFunction")
  local function cb() return 1 end
  bf.OnInvoke = cb
  expect(f(bf, "OnInvoke") == cb, "callback value mismatch")
end)

T("getconnections", "Instances", function(f)
  local ev = Instance.new("BindableEvent")
  local hits = 0
  local function cb() hits = hits + 1 end
  ev.Event:Connect(cb)
  local conns = f(ev.Event)
  expect(#conns == 1, "should find 1 connection")
  expect(conns[1].Function == cb, "Function field mismatch")
  conns[1]:Disable()
  ev:Fire()
  expect(hits == 0, "disabled connection still fired")
  conns[1]:Enable()
  ev:Fire()
  expect(hits == 1, "enabled connection did not fire")
  conns[1]:Fire()
  expect(hits == 2, "Fire() did not call the handler")
end)

T("gethiddenproperty", "Instances", function(f)
  local fire = Instance.new("Fire")
  local v, hidden = f(fire, "size_xml")
  expect(type(v) == "number" and hidden == true, "hidden property mismatch")
  local _, h2 = f(fire, "Enabled")
  expect(h2 == false, "normal property reported as hidden")
end)

T("sethiddenproperty", "Instances", function(f)
  local fire = Instance.new("Fire")
  f(fire, "size_xml", 11)
  expect(R("gethiddenproperty")(fire, "size_xml") == 11, "value was not stored")
end)

T("isscriptable", "Instances", function(f)
  local fire = Instance.new("Fire")
  expect(f(fire, "size_xml") == false, "hidden property should not be scriptable")
  expect(f(fire, "Enabled") == true, "normal property should be scriptable")
end)

T("setscriptable", "Instances", function(f)
  local fire = Instance.new("Fire")
  local was = f(fire, "size_xml", true)
  expect(was == false, "should return the previous state")
  expect(R("isscriptable")(fire, "size_xml") == true, "property did not become scriptable")
  expect(fire.size_xml ~= nil, "property is still inaccessible")
end)

T("gethui", "Instances", function(f)
  local hui = f()
  expect(typeof(hui) == "Instance", "should return an Instance")
  local gui = Instance.new("ScreenGui")
  gui.Parent = hui
  expect(gui.Parent == hui, "could not parent to the hidden UI")
  gui:Destroy()
end)

T("getinstances", "Instances", function(f)
  local part = tmp("Part")
  expect(contains(f(), part), "new part not listed")
end)

T("getnilinstances", "Instances", function(f)
  local part = Instance.new("Part")
  expect(contains(f(), part), "nil-parented part not listed")
end)

T("setrbxclipboard", "Instances", function(f)
  f("sunc clipboard")
end)

T("fireproximityprompt", "Instances", function(f)
  local pp = Instance.new("ProximityPrompt", tmp("Part"))
  local fired = 0
  pp.Triggered:Connect(function() fired = fired + 1 end)
  f(pp)
  expect(fired == 1, "Triggered did not fire")
  f(pp, 2)
  expect(fired == 3, "amount argument ignored")
end)

T("firetouchinterest", "Instances", function(f)
  local a, b = tmp("Part"), tmp("Part")
  local touched = false
  b.Touched:Connect(function() touched = true end)
  f(a, b, 0)
  expect(touched, "Touched did not fire")
end)

T("firesignal", "Instances", function(f)
  local ev = Instance.new("BindableEvent")
  local a, b
  ev.Event:Connect(function(x, y) a, b = x, y end)
  f(ev.Event, 1, 2)
  expect(a == 1 and b == 2, "arguments were not passed through")
end)

T("replicatesignal", "Instances", function(f)
  local ev = Instance.new("BindableEvent")
  local got
  ev.Event:Connect(function(x) got = x end)
  f(ev.Event, "hi")
  expect(got == "hi", "signal did not fire")
end)

------------------------------------------------------------------------
-- Metatable
------------------------------------------------------------------------
T("getrawmetatable", "Metatable", function(f)
  local obj = setmetatable({}, { __metatable = "Locked!" })
  expect(getmetatable(obj) == "Locked!", "setup failed")
  expect(type(f(obj)) == "table", "should bypass __metatable")
  expect(type(f(game)) == "table", "should return the game metatable")
end)

T("hookmetamethod", "Metatable", function(f)
  local obj = setmetatable({}, { __index = function() return false end })
  local ref = f(obj, "__index", function() return true end)
  expect(obj.test == true, "__index was not hooked")
  expect(ref() == false, "original metamethod was not returned")
  local calls = 0
  local old
  old = f(game, "__namecall", function(self, ...)
    calls = calls + 1
    return old(self, ...)
  end)
  game:GetService("Workspace")
  f(game, "__namecall", old)
  expect(calls >= 1, "__namecall hook was not called")
end)

T("getnamecallmethod", "Metatable", function(f)
  local seen
  local old
  old = R("hookmetamethod")(game, "__namecall", function(self, ...)
    seen = f()
    return old(self, ...)
  end)
  workspace:GetChildren()
  R("hookmetamethod")(game, "__namecall", old)
  expect(seen == "GetChildren", "wrong namecall method: " .. tostring(seen))
end)

T("isreadonly", "Metatable", function(f)
  local t = {}
  expect(f(t) == false, "new table should not be readonly")
  table.freeze(t)
  expect(f(t) == true, "frozen table should be readonly")
end)

T("setrawmetatable", "Metatable", function(f)
  local t = {}
  f(t, { __index = function() return 5 end })
  expect(t.anything == 5, "metatable was not applied")
end)

T("setreadonly", "Metatable", function(f)
  local t = { x = 1 }
  f(t, true)
  expect(not pcall(function() t.y = 2 end), "write to readonly table succeeded")
  expect(t.x == 1, "existing value lost")
  f(t, false)
  t.y = 2
  expect(t.y == 2, "table is still readonly")
end)

------------------------------------------------------------------------
-- Miscellaneous
------------------------------------------------------------------------
T("identifyexecutor", "Miscellaneous", function(f)
  local name, version = f()
  expect(type(name) == "string" and #name > 0, "name missing")
  expect(type(version) == "string", "version missing")
end)

T("messagebox", "Miscellaneous", function(f)
  expect(type(f("sUNC", "test", 0)) == "number", "should return a button code")
end)

T("queue_on_teleport", "Miscellaneous", function(f)
  f("print('queued script ran')")
end)

T("request", "Miscellaneous", function(f)
  expect(not pcall(f, {}), "should reject a request without Url")
  local ok, res = pcall(f, { Url = "https://example.com", Method = "GET" })
  expect(ok, "request failed (no internet?): " .. tostring(res))
  expect(res.StatusCode == 200 and res.Success == true, "unexpected status " .. tostring(res.StatusCode))
  expect(type(res.Body) == "string" and #res.Body > 0, "empty body")
  expect(type(res.Headers) == "table", "headers missing")
end)

T("setclipboard", "Miscellaneous", function(f)
  f("sunc clipboard test")
  expect(H.clip_get() == "sunc clipboard test", "clipboard not updated")
end)

T("setfpscap", "Miscellaneous", function(f)
  f(60)
  f(0)
end)

T("getfpscap", "Miscellaneous", function(f)
  R("setfpscap")(75)
  expect(f() == 75, "did not return the cap that was set")
  R("setfpscap")(0)
end)

T("setnamecallmethod", "Metatable", function(f)
  expect(pcall(f, "Foo") == true, "should accept a string")
  expect(not pcall(f, 123), "should reject non-strings")
end)

T("isluau", "Miscellaneous", function(f)
  expect(f() == true, "should return true")
end)

T("isnetworkowner", "Instances", function(f)
  local part = tmp("Part")
  expect(type(f(part)) == "boolean", "should return a boolean")
  expect(not pcall(f, 123), "should reject non-instances")
end)

T("decompile", "Scripts", function(f)
  local m = Instance.new("ModuleScript")
  m.Source = "return 1"
  local out = f(m)
  expect(type(out) == "string" and #out > 0, "should return source text")
  m:Destroy()
end)

------------------------------------------------------------------------
-- Scripts / environment / reflection
------------------------------------------------------------------------
T("getgc", "Scripts", function(f)
  local function sunc_gc_marker() return 1 end
  local gc = f()
  expect(type(gc) == "table" and #gc > 0, "should return a list")
  expect(contains(gc, sunc_gc_marker), "live function not found")
  local tbl = { sunc_gc_table_key = true }
  local all = f(true)
  local found = false
  for _, v in pairs(all) do
    if type(v) == "table" and rawget(v, "sunc_gc_table_key") then found = true end
  end
  expect(found, "live table not found with includeTables = true")
end)

T("getgenv", "Scripts", function(f)
  f().sunc_flag = 123
  expect(sunc_flag == 123, "global was not written")
  f().sunc_flag = nil
end)

T("getloadedmodules", "Scripts", function(f)
  local list = f()
  expect(type(list) == "table" and #list > 0, "should list modules")
  expect(list[1]:IsA("ModuleScript"), "entries should be ModuleScripts")
end)

T("getrenv", "Scripts", function(f)
  local env = f()
  expect(type(env) == "table" and env.print ~= nil, "environment looks wrong")
  expect(env.game == game, "game missing from the Roblox environment")
end)

T("getrunningscripts", "Scripts", function(f)
  local list = f()
  expect(type(list) == "table" and #list > 0, "should list running scripts")
  expect(typeof(list[1]) == "Instance", "entries should be Instances")
end)

T("getscriptbytecode", "Scripts", function(f)
  local m = tmp("ModuleScript")
  m.Source = "return 1"
  local b = f(m)
  expect(type(b) == "string" and #b > 0, "should return a string")
  expect(not pcall(f, workspace), "should reject non-scripts")
end)

T("getscripthash", "Scripts", function(f)
  local m = tmp("ModuleScript")
  m.Source = "return 1"
  local h1 = f(m)
  expect(type(h1) == "string" and #h1 == 96, "should be a SHA-384 hex string")
  m.Source = "return 2"
  expect(f(m) ~= h1, "hash did not change with the source")
end)

T("getscripts", "Scripts", function(f)
  local m = tmp("ModuleScript")
  expect(contains(f(), m), "new script not listed")
end)

T("getsenv", "Scripts", function(f)
  local loader = game.Players.LocalPlayer.PlayerScripts.PlayerScriptsLoader
  local env = f(loader)
  expect(type(env) == "table", "should return a table")
  expect(env.script == loader, "env.script mismatch")
  expect(not pcall(f, tmp("LocalScript", false)), "unstarted script should error")
end)

T("getthreadidentity", "Scripts", function(f)
  expect(type(f()) == "number", "should return a number")
end)

T("setthreadidentity", "Scripts", function(f)
  local old = R("getthreadidentity")()
  f(3)
  expect(R("getthreadidentity")() == 3, "identity was not changed")
  f(old)
end)

T("getreg", "Scripts", function(f)
  local co = coroutine.create(function() end)
  local reg = f()
  expect(type(reg) == "table", "should return a table")
  expect(contains(reg, co), "thread not found in the registry")
end)

T("filtergc", "Scripts", function(f)
  local function sunc_filter_target() return 1 end
  local r = f("function", { Name = "sunc_filter_target", IgnoreExecutor = false }, true)
  expect(r == sunc_filter_target, "function filter failed")
  local t = { sunc_filter_key = true }
  local tr = f("table", { Keys = { "sunc_filter_key" } }, true)
  expect(tr == t, "table filter failed")
  expect(not pcall(f, "bogus", {}), "invalid type should error")
end)

T("getscriptfromthread", "Scripts", function(f)
  local co = coroutine.create(function() end)
  expect(f(co) == nil, "unknown thread should give nil")
  local loader = game.Players.LocalPlayer.PlayerScripts.PlayerScriptsLoader
  local thread = X.D[loader].thread
  expect(f(thread) == loader, "script of a running thread not found")
end)

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
T("Drawing", "Drawing", function(f)
  expect(type(f) == "table", "Drawing should be a table")
end)

T("Drawing.new", "Drawing", function(f)
  for _, kind in ipairs({ "Line", "Text", "Image", "Circle", "Square", "Quad", "Triangle" }) do
    local o = f(kind)
    o.Visible = true
    expect(o.Visible == true, kind .. ": property not stored")
    o:Remove()
  end
  expect(not pcall(f, "Nope"), "invalid type should error")
end)

T("Drawing.Fonts", "Drawing", function(f)
  expect(f.UI == 0 and f.System == 1 and f.Plex == 2 and f.Monospace == 3, "font ids mismatch")
end)

T("isrenderobj", "Drawing", function(f)
  local o = Drawing.new("Circle")
  expect(f(o) == true, "should be true for a Drawing")
  expect(f({}) == false and f(1) == false, "should be false for other values")
  o:Remove()
end)

T("getrenderproperty", "Drawing", function(f)
  local sq = Drawing.new("Square")
  sq.Size = Vector2.new(5, 6)
  expect(f(sq, "Size") == sq.Size, "wrong value")
  expect(not pcall(f, sq, "Nope"), "invalid property should error")
  sq:Remove()
end)

T("setrenderproperty", "Drawing", function(f)
  local c = Drawing.new("Circle")
  f(c, "Radius", 7)
  expect(c.Radius == 7, "value was not set")
  c:Remove()
end)

T("cleardrawcache", "Drawing", function(f)
  local o = Drawing.new("Line")
  f()
  expect(R("isrenderobj")(o) == false, "objects survived cleardrawcache")
end)

------------------------------------------------------------------------
-- WebSocket
------------------------------------------------------------------------
T("WebSocket", "WebSocket", function(f)
  expect(type(f) == "table", "WebSocket should be a table")
end)

T("WebSocket.connect", "WebSocket", function(f)
  local ws = f("wss://echo.websocket.org")
  local got
  ws.OnMessage:Connect(function(m) got = m end)
  ws:Send("ping")
  task.wait(0.1)
  expect(got == "ping", "echo message was not received")
  local closed = false
  ws.OnClose:Connect(function() closed = true end)
  ws:Close()
  expect(closed, "OnClose did not fire")
  expect(not pcall(f, "http://not-a-websocket"), "invalid url should error")
end)

------------------------------------------------------------------------
-- runner
------------------------------------------------------------------------
local function cleanup()
  for _, i in ipairs(TMP) do
    pcall(function() i:Destroy() end)
  end
  TMP = {}
end

local function shortErr(err)
  local s = tostring(err)
  s = s:gsub("^executor_tests:%d+:%s*", "")
  if #s > 200 then s = s:sub(1, 200) .. "..." end
  return s
end

G.__run_sunc = function()
  local delfolder = resolve("delfolder")
  if delfolder then pcall(delfolder, DIR) end
  H.test_begin(#tests)
  X.quietLoad = true
  for _, t in ipairs(tests) do
    local fn = resolve(t.name)
    if fn == nil then
      H.test_result(t.name, t.category, "missing", "function does not exist")
    else
      local ok, err = pcall(t.fn, fn)
      cleanup()
      if not ok then
        H.test_result(t.name, t.category, "fail", shortErr(err))
      else
        local def = X.DEFS[t.name]
        local missing = {}
        if def then
          for _, a in ipairs(def.aliases) do
            if resolve(a) == nil then missing[#missing + 1] = a end
          end
        end
        if #missing > 0 then
          H.test_result(t.name, t.category, "warn", "aliases missing: " .. table.concat(missing, ", "))
        else
          H.test_result(t.name, t.category, "pass", "")
        end
      end
    end
  end
  if delfolder then pcall(delfolder, DIR) end
  H.draw_flush()
  X.quietLoad = false
  H.test_end()
end
