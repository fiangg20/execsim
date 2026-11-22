-- unc_core.lua : UNC / sUNC functions, part 1
-- cache, closures, metatable, instances/signals, scripts, debug, environment, reflection

local H = __host
local G = _G
local X = H.X
local rawtype = H.rawtype
local dbg = debug
local D = X.D
local typeof = X.typeof
local isInstance = X.isInstance
local InstMT = X.InstMT

------------------------------------------------------------------------
-- definition registry (used for aliases, profiles, coverage)
------------------------------------------------------------------------
local DEFS = {}
X.DEFS = DEFS

local function splitPath(path)
  local t = {}
  for p in string.gmatch(path, "[^.]+") do t[#t + 1] = p end
  return t
end

local function setpath(path, v)
  local ps = splitPath(path)
  local cur = G
  for i = 1, #ps - 1 do
    local nxt = cur[ps[i]]
    if rawtype(nxt) ~= "table" then
      nxt = {}
      cur[ps[i]] = nxt
    end
    cur = nxt
  end
  cur[ps[#ps]] = v
end

local function getpath(path)
  local cur = G
  for _, p in ipairs(splitPath(path)) do
    if rawtype(cur) ~= "table" then return nil end
    cur = cur[p]
    if cur == nil then return nil end
  end
  return cur
end

local function def(name, v, ...)
  local aliases = { ... }
  DEFS[name] = { value = v, aliases = aliases }
  setpath(name, v)
  for _, a in ipairs(aliases) do setpath(a, v) end
end
X.def = def

G.__exists = function(name) return getpath(name) ~= nil end

local cwrap = H.cwrap
X.cwrap = cwrap

local function argError(n, fname, expected, got)
  error("invalid argument #" .. n .. " to '" .. fname .. "' (" .. expected .. " expected, got " .. typeof(got) .. ")", 3)
end
X.argError = argError

local function needInstance(v, n, fname)
  if not isInstance(v) then argError(n, fname, "Instance", v) end
  return D[v]
end

local function needFunction(v, n, fname)
  if rawtype(v) ~= "function" then argError(n, fname, "function", v) end
end

local function has(s, sub) return string.find(s, sub, 1, true) ~= nil end

------------------------------------------------------------------------
-- cache
------------------------------------------------------------------------
local function replaceProxy(d, newProxy)
  if d.parent then
    local pd = D[d.parent]
    for i = 1, #pd.children do
      if pd.children[i] == d.proxy then pd.children[i] = newProxy end
    end
  end
  for _, c in ipairs(d.children) do D[c].parent = newProxy end
  d.proxy = newProxy
end

def("cloneref", function(inst)
  local d = needInstance(inst, 1, "cloneref")
  local p = setmetatable({}, InstMT)
  D[p] = d
  return p
end)

def("compareinstances", function(a, b)
  local da = needInstance(a, 1, "compareinstances")
  local db = needInstance(b, 2, "compareinstances")
  return da == db
end)

def("cache.invalidate", function(inst)
  local d = needInstance(inst, 1, "cache.invalidate")
  local np = setmetatable({}, InstMT)
  D[np] = d
  replaceProxy(d, np)
end)

def("cache.iscached", function(inst)
  local d = needInstance(inst, 1, "cache.iscached")
  return d.proxy == inst
end)

def("cache.replace", function(a, b)
  local da = needInstance(a, 1, "cache.replace")
  needInstance(b, 2, "cache.replace")
  D[b] = da
  replaceProxy(da, b)
end)

------------------------------------------------------------------------
-- closures
------------------------------------------------------------------------
local function srcOf(f) return H.fsource(f) or "" end

local function isCnative(f)
  if H.fkind(f) == "java" then return true end
  local s = srcOf(f)
  return has(s, "game_env") or has(s, "exec_")
end

local function isExecClosure(f)
  if H.iscwrapped(f) then return true end
  if H.fkind(f) ~= "lua" then return false end
  return not has(srcOf(f), "game_")
end

def("iscclosure", function(f)
  needFunction(f, 1, "iscclosure")
  return isCnative(f)
end)

def("islclosure", function(f)
  needFunction(f, 1, "islclosure")
  return not isCnative(f)
end)

def("isexecutorclosure", function(f)
  needFunction(f, 1, "isexecutorclosure")
  return isExecClosure(f)
end, "checkclosure", "isourclosure")

def("newcclosure", function(f)
  needFunction(f, 1, "newcclosure")
  return H.cwrap(f)
end)

def("clonefunction", function(f)
  needFunction(f, 1, "clonefunction")
  if H.fkind(f) == "lua" then
    local c = H.fclone(f)
    if c then return c end
    return function(...) return f(...) end
  end
  return H.cwrap(f)
end)

def("checkcaller", function() return X.callerGame == 0 end)

def("getcallingscript", function() return X.currentScript end)

def("loadstring", function(code, chunkname)
  if rawtype(code) ~= "string" then argError(1, "loadstring", "string", code) end
  local fn, err = load(H.luau(code), "executor_chunk", "t", G)
  if not fn then return nil, err end
  return fn
end)

def("getscriptclosure", function(script)
  local d = needInstance(script, 1, "getscriptclosure")
  if not X.isA(d.class, "LuaSourceContainer") then argError(1, "getscriptclosure", "script", script) end
  local ok, fn = pcall(X.compileScript, script)
  if not ok then error(fn, 0) end
  return fn
end, "getscriptfunction")

def("getfunctionhash", function(f)
  needFunction(f, 1, "getfunctionhash")
  if H.fkind(f) ~= "lua" then error("invalid argument #1 to 'getfunctionhash' (Lua function expected)", 2) end
  return H.fhash(f)
end)

-- hookfunction / restorefunction ----------------------------------------
local HOOKS = setmetatable({}, { __mode = "k" })

local function replaceRefs(old, new)
  local replaced = {}
  local seen = {}
  local function scan(t, depth)
    if seen[t] or depth > 3 then return end
    seen[t] = true
    for k, v in next, t do
      if v == old then
        t[k] = new
        replaced[#replaced + 1] = { t, k }
      elseif rawtype(v) == "table" and not isInstance(v) and v ~= D then
        scan(v, depth + 1)
      end
    end
  end
  scan(G, 0)
  scan(X.RENV, 0)
  return replaced
end

local function makeForwarder(hook)
  local h = hook
  return function(...) return h(...) end
end

def("hookfunction", function(f, hook)
  needFunction(f, 1, "hookfunction")
  needFunction(hook, 2, "hookfunction")
  if H.fkind(f) == "lua" then
    local orig = H.fclone(f)
    if orig then
      local fwd = makeForwarder(hook)
      if H.fpatch(f, fwd) then
        HOOKS[f] = { kind = "lua", orig = orig }
        return orig
      end
    end
  end
  local refs = replaceRefs(f, hook)
  HOOKS[f] = { kind = "refs", refs = refs, hook = hook }
  return f
end, "replaceclosure")

def("restorefunction", function(f)
  needFunction(f, 1, "restorefunction")
  local info = HOOKS[f]
  if not info then return end
  if info.kind == "lua" then
    H.fpatch(f, info.orig)
  else
    for _, r in ipairs(info.refs) do
      if r[1][r[2]] == info.hook then r[1][r[2]] = f end
    end
  end
  HOOKS[f] = nil
end)

------------------------------------------------------------------------
-- metatable
------------------------------------------------------------------------
local ROINFO = setmetatable({}, { __mode = "k" })
local ROFLAG = {}
ROFLAG[InstMT] = true

local opairs, oipairs = pairs, ipairs
G.pairs = function(t)
  local info = ROINFO[t]
  if info then return next, info.shadow, nil end
  return opairs(t)
end
G.ipairs = function(t)
  local info = ROINFO[t]
  if info then return oipairs(info.shadow) end
  return oipairs(t)
end

local function freeze(t)
  if ROINFO[t] then return t end
  local shadow = {}
  for k, v in next, t do shadow[k] = v end
  for k in next, shadow do t[k] = nil end
  local oldmt = dbg.getmetatable(t)
  local mt = {}
  if oldmt then for k, v in next, oldmt do mt[k] = v end end
  local oi = mt.__index
  mt.__index = function(_, k)
    local v = shadow[k]
    if v == nil and oi ~= nil then
      if rawtype(oi) == "function" then return oi(t, k) end
      return oi[k]
    end
    return v
  end
  mt.__newindex = function(_, k) error("Attempt to modify a readonly table", 2) end
  mt.__len = function() return #shadow end
  ROINFO[t] = { shadow = shadow, oldmt = oldmt }
  dbg.setmetatable(t, mt)
  return t
end

local function thaw(t)
  local info = ROINFO[t]
  if not info then return t end
  dbg.setmetatable(t, info.oldmt)
  for k, v in next, info.shadow do rawset(t, k, v) end
  ROINFO[t] = nil
  return t
end

G.table.freeze = freeze
G.table.isfrozen = function(t) return ROINFO[t] ~= nil end

def("setreadonly", function(t, state)
  if rawtype(t) ~= "table" then argError(1, "setreadonly", "table", t) end
  if rawtype(state) ~= "boolean" then argError(2, "setreadonly", "boolean", state) end
  if ROFLAG[t] ~= nil then
    ROFLAG[t] = state
    return
  end
  if state then freeze(t) else thaw(t) end
end)

def("isreadonly", function(t)
  if rawtype(t) ~= "table" then argError(1, "isreadonly", "table", t) end
  return ROFLAG[t] == true or ROINFO[t] ~= nil
end)

def("getrawmetatable", function(obj)
  local t = rawtype(obj)
  if t == "nil" or t == "boolean" or t == "number" then
    argError(1, "getrawmetatable", "table", obj)
  end
  return dbg.getmetatable(obj)
end)

def("setrawmetatable", function(obj, mt)
  if rawtype(obj) ~= "table" then argError(1, "setrawmetatable", "table", obj) end
  if mt ~= nil and rawtype(mt) ~= "table" then argError(2, "setrawmetatable", "table", mt) end
  dbg.setmetatable(obj, mt)
  return obj
end)

def("hookmetamethod", function(obj, mm, hook)
  if rawtype(mm) ~= "string" then argError(2, "hookmetamethod", "string", mm) end
  needFunction(hook, 3, "hookmetamethod")
  local mt = dbg.getmetatable(obj)
  if rawtype(mt) ~= "table" then error("invalid argument #1 to 'hookmetamethod' (object has no metatable)", 2) end
  local old = rawget(mt, mm)
  local oldfn
  if rawtype(old) == "function" then
    oldfn = old
  elseif rawtype(old) == "table" and mm == "__index" then
    oldfn = function(_, k) return old[k] end
  elseif old == nil then
    oldfn = function() end
  else
    oldfn = function() return old end
  end
  rawset(mt, mm, hook)
  return oldfn
end)

def("getnamecallmethod", function() return X.getNamecall() end)

def("setnamecallmethod", function(name)
  if rawtype(name) ~= "string" then argError(1, "setnamecallmethod", "string", name) end
  X.setNamecall(name)
end)

def("isluau", function() return true end)

def("isnetworkowner", function(part)
  local d = needInstance(part, 1, "isnetworkowner")
  if not X.isA(d.class, "BasePart") then argError(1, "isnetworkowner", "BasePart", part) end
  return true
end)

------------------------------------------------------------------------
-- instances / signals
------------------------------------------------------------------------
local function LP() return X.localPlayer end

def("fireclickdetector", function(cd, distance, event)
  local d = needInstance(cd, 1, "fireclickdetector")
  if d.class ~= "ClickDetector" then argError(1, "fireclickdetector", "ClickDetector", cd) end
  event = event or "MouseClick"
  local sig = d.signals[event]
  if not sig then error("invalid argument #3 to 'fireclickdetector' (invalid event name)", 2) end
  X.fire(sig, LP())
end)

def("fireproximityprompt", function(pp, amount, skip)
  local d = needInstance(pp, 1, "fireproximityprompt")
  if d.class ~= "ProximityPrompt" then argError(1, "fireproximityprompt", "ProximityPrompt", pp) end
  for _ = 1, (amount or 1) do
    X.fire(d.signals.PromptButtonHoldBegan, LP())
    X.fire(d.signals.Triggered, LP())
    X.fire(d.signals.PromptButtonHoldEnded, LP())
    X.fire(d.signals.TriggerEnded, LP())
  end
end)

def("firetouchinterest", function(a, b, state)
  local da = needInstance(a, 1, "firetouchinterest")
  local db = needInstance(b, 2, "firetouchinterest")
  if not X.isA(da.class, "BasePart") then argError(1, "firetouchinterest", "BasePart", a) end
  if not X.isA(db.class, "BasePart") then argError(2, "firetouchinterest", "BasePart", b) end
  local begin = (state == nil or state == 0 or state == true)
  if begin then
    X.fire(db.signals.Touched, a)
    X.fire(da.signals.Touched, b)
  else
    X.fire(db.signals.TouchEnded, a)
    X.fire(da.signals.TouchEnded, b)
  end
end)

local function fireSignalImpl(fname)
  return function(sig, ...)
    if typeof(sig) ~= "RBXScriptSignal" then argError(1, fname, "RBXScriptSignal", sig) end
    X.fire(sig, ...)
  end
end
def("firesignal", fireSignalImpl("firesignal"))
def("replicatesignal", fireSignalImpl("replicatesignal"))

local function wrapConn(rec)
  local methods = {
    Fire = function(_, ...)
      if rec.fn and rec.connected then rec.fn(...) end
    end,
    Defer = function(_, ...)
      local args = { n = select("#", ...), ... }
      G.task.defer(function()
        if rec.fn and rec.connected then rec.fn(table.unpack(args, 1, args.n)) end
      end)
    end,
    Disconnect = function()
      if rec.handle then rec.handle:Disconnect() elseif rec.sig then X.removeRec(rec) end
    end,
    Disable = function() rec.enabled = false end,
    Enable = function() rec.enabled = true end,
  }
  local mt = { __rbxtype = "RBXScriptConnection" }
  mt.__index = function(_, k)
    if methods[k] then return methods[k] end
    if k == "Enabled" or k == "State" then return rec.enabled end
    if k == "ForeignState" then return rec.foreign == true end
    if k == "LuaConnection" then return not rec.foreign end
    if k == "Function" then return rec.fn end
    if k == "Thread" then return rec.thread end
    if k == "Connected" then return rec.connected end
    return nil
  end
  mt.__newindex = function(_, k, v)
    if k == "Enabled" then rec.enabled = v and true or false
    else error("cannot modify connection field " .. tostring(k), 2) end
  end
  return setmetatable({}, mt)
end

def("getconnections", function(sig)
  if typeof(sig) ~= "RBXScriptSignal" then argError(1, "getconnections", "RBXScriptSignal", sig) end
  local out = {}
  for i, rec in ipairs(sig.__conns) do out[i] = wrapConn(rec) end
  return out
end)

def("getcallbackvalue", function(inst, prop)
  local d = needInstance(inst, 1, "getcallbackvalue")
  if rawtype(prop) ~= "string" then argError(2, "getcallbackvalue", "string", prop) end
  if not d.callbacks[prop] then
    error(prop .. " is not a valid callback member of " .. d.class, 2)
  end
  return d.cbvalues and d.cbvalues[prop]
end)

def("gethiddenproperty", function(inst, prop)
  local d = needInstance(inst, 1, "gethiddenproperty")
  if rawtype(prop) ~= "string" then argError(2, "gethiddenproperty", "string", prop) end
  if d.hprops[prop] ~= nil then return d.hprops[prop], true end
  local v = d.props[prop]
  if v ~= nil then return v, false end
  error(prop .. " is not a valid member of " .. d.class, 2)
end)

def("sethiddenproperty", function(inst, prop, value)
  local d = needInstance(inst, 1, "sethiddenproperty")
  if rawtype(prop) ~= "string" then argError(2, "sethiddenproperty", "string", prop) end
  if d.hprops[prop] ~= nil then
    d.hprops[prop] = value
    return true
  end
  if d.props[prop] ~= nil then
    d.props[prop] = value
    return false
  end
  error(prop .. " is not a valid member of " .. d.class, 2)
end)

def("isscriptable", function(inst, prop)
  local d = needInstance(inst, 1, "isscriptable")
  if rawtype(prop) ~= "string" then argError(2, "isscriptable", "string", prop) end
  if d.hprops[prop] ~= nil then return d.scriptable[prop] == true end
  if d.props[prop] ~= nil or d.signals[prop] ~= nil then return true end
  return nil
end)

def("setscriptable", function(inst, prop, state)
  local d = needInstance(inst, 1, "setscriptable")
  if rawtype(prop) ~= "string" then argError(2, "setscriptable", "string", prop) end
  if rawtype(state) ~= "boolean" then argError(3, "setscriptable", "boolean", state) end
  if d.hprops[prop] ~= nil then
    local was = d.scriptable[prop] == true
    d.scriptable[prop] = state
    return was
  end
  if d.props[prop] ~= nil then
    if state == false then
      d.hprops[prop] = d.props[prop]
      d.props[prop] = nil
      d.scriptable[prop] = false
    end
    return true
  end
  return nil
end)

def("gethui", function() return X.hui end)

def("getinstances", function()
  local out = {}
  for _, d in ipairs(X.ALLDATA) do
    if not d.destroyed and d.class ~= "DataModel" then out[#out + 1] = d.proxy end
  end
  return out
end)

def("getnilinstances", function()
  local out = {}
  for _, d in ipairs(X.ALLDATA) do
    if not d.destroyed and d.parent == nil and d.class ~= "DataModel" then out[#out + 1] = d.proxy end
  end
  return out
end)

local function setClip(text, fname)
  if rawtype(text) ~= "string" then argError(1, fname, "string", text) end
  H.clip_set(text)
end
def("setrbxclipboard", function(text) setClip(text, "setrbxclipboard") end)

------------------------------------------------------------------------
-- scripts / environment / reflection
------------------------------------------------------------------------
local function needScript(v, n, fname)
  local d = needInstance(v, n, fname)
  if not X.isA(d.class, "LuaSourceContainer") then argError(n, fname, "script", v) end
  return d
end

def("getscripts", function()
  local out = {}
  for _, d in ipairs(X.ALLDATA) do
    if not d.destroyed and X.isA(d.class, "LuaSourceContainer") then out[#out + 1] = d.proxy end
  end
  return out
end)

def("getrunningscripts", function()
  local out = {}
  for _, d in ipairs(X.ALLDATA) do
    if not d.destroyed and d.running and X.isA(d.class, "LuaSourceContainer") then out[#out + 1] = d.proxy end
  end
  return out
end)

def("getloadedmodules", function()
  local out = {}
  for _, d in ipairs(X.ALLDATA) do
    if not d.destroyed and d.loaded and d.class == "ModuleScript" then out[#out + 1] = d.proxy end
  end
  return out
end)

def("getsenv", function(script)
  local d = needScript(script, 1, "getsenv")
  if not (d.running or d.loaded) or not d.env then
    error("invalid argument #1 to 'getsenv' (script is not running)", 2)
  end
  return d.env
end)

local function bytecodeOf(script, fname)
  local d = needScript(script, 1, fname)
  return string.char(6, 4) .. tostring(d.props.Source or "")
end

def("getscriptbytecode", function(script) return bytecodeOf(script, "getscriptbytecode") end, "dumpstring")

def("decompile", function(script)
  local d = needScript(script, 1, "decompile")
  return "-- Decompiled with ExecSim\n" .. tostring(d.props.Source or "")
end)

def("getscripthash", function(script)
  return H.hash("sha384", bytecodeOf(script, "getscripthash"))
end)

def("getscriptfromthread", function(thread)
  if rawtype(thread) ~= "thread" then argError(1, "getscriptfromthread", "thread", thread) end
  for _, d in ipairs(X.ALLDATA) do
    if d.thread == thread then return d.proxy end
  end
  return nil
end)

def("getthreadidentity", function() return X.identity end, "getidentity", "getthreadcontext")

local function setIdentity(n)
  if rawtype(n) ~= "number" then argError(1, "setthreadidentity", "number", n) end
  if n < 0 or n > 9 then error("invalid argument #1 to 'setthreadidentity' (identity out of range)", 2) end
  X.identity = math.floor(n)
end
def("setthreadidentity", setIdentity, "setidentity", "setthreadcontext")

def("getgenv", function() return G end)
def("getrenv", function() return X.RENV end)

-- getgc: walk everything reachable from the roots -----------------------
local dgetup = dbg.getupvalue
local dsetup = dbg.setupvalue
local dgetlocal = dbg.getlocal
local dsetlocal = dbg.setlocal
local dgetinfo = dbg.getinfo

local function collect(includeTables)
  local seen = {}
  local out = {}
  local names = {}
  local queue = {}
  local function visit(v, name)
    local t = rawtype(v)
    if t ~= "function" and t ~= "table" and t ~= "thread" then return end
    if name and names[v] == nil and rawtype(name) == "string" then names[v] = name end
    if seen[v] then return end
    seen[v] = true
    queue[#queue + 1] = v
  end
  seen[queue] = true
  seen[out] = true
  seen[names] = true
  seen[seen] = true
  visit(G); visit(X.RENV); visit(X.SHARED); visit(package and package.loaded)
  for lvl = 1, 120 do
    local ok = pcall(function()
      local i = 1
      while true do
        local n, v = dgetlocal(lvl, i)
        if n == nil then break end
        visit(v, n)
        i = i + 1
      end
    end)
    if not ok then break end
  end
  local qi = 1
  local budget = 60000
  while qi <= #queue and budget > 0 do
    budget = budget - 1
    local v = queue[qi]
    qi = qi + 1
    local t = rawtype(v)
    if t == "function" then
      out[#out + 1] = v
      if H.fkind(v) == "lua" then
        local i = 1
        while true do
          local n, uv = dgetup(v, i)
          if n == nil then break end
          visit(uv, n)
          i = i + 1
        end
      end
    elseif t == "table" then
      if includeTables then out[#out + 1] = v end
      local info = ROINFO[v]
      local src = info and info.shadow or v
      local count = 0
      for k, val in next, src do
        count = count + 1
        if count > 4000 then break end
        visit(k)
        visit(val, k)
      end
      local mt = dbg.getmetatable(v)
      if rawtype(mt) == "table" then visit(mt) end
    elseif t == "thread" then
      out[#out + 1] = v
    end
  end
  return out, names
end

def("getgc", function(includeTables)
  local out = collect(includeTables == true)
  return out
end)

def("getreg", function()
  local out = {}
  for co in pairs(X.THREADS) do out[#out + 1] = co end
  local gc = collect(false)
  for _, f in ipairs(gc) do out[#out + 1] = f end
  return out
end)

local function hasAll(haystack, needles)
  for _, n in ipairs(needles) do
    local found = false
    for _, h in ipairs(haystack) do
      if h == n then found = true; break end
    end
    if not found then return false end
  end
  return true
end

def("filtergc", function(kind, options, returnOne)
  if kind ~= "function" and kind ~= "table" then
    error("invalid argument #1 to 'filtergc' (expected 'function' or 'table')", 2)
  end
  options = options or {}
  if rawtype(options) ~= "table" then argError(2, "filtergc", "table", options) end
  local all, names = collect(kind == "table")
  local results = {}
  for _, v in ipairs(all) do
    local ok = false
    if kind == "function" and rawtype(v) == "function" then
      ok = true
      if options.IgnoreExecutor ~= false and isExecClosure(v) then ok = false end
      if ok and options.Name ~= nil and names[v] ~= options.Name then ok = false end
      if ok and options.Hash ~= nil then
        if H.fkind(v) ~= "lua" or H.fhash(v) ~= options.Hash then ok = false end
      end
      if ok and options.Constants ~= nil then
        if H.fkind(v) ~= "lua" or not hasAll(H.consts(v), options.Constants) then ok = false end
      end
      if ok and options.Upvalues ~= nil then
        local ups = {}
        if H.fkind(v) == "lua" then
          local i = 1
          while true do
            local n, uv = dgetup(v, i)
            if n == nil then break end
            if n ~= "_ENV" then ups[#ups + 1] = uv end
            i = i + 1
          end
        end
        if not hasAll(ups, options.Upvalues) then ok = false end
      end
    elseif kind == "table" and rawtype(v) == "table" then
      ok = true
      local info = ROINFO[v]
      local src = info and info.shadow or v
      if options.Keys ~= nil then
        for _, k in ipairs(options.Keys) do if src[k] == nil then ok = false end end
      end
      if ok and options.Values ~= nil then
        local vals = {}
        for _, x in next, src do vals[#vals + 1] = x end
        if not hasAll(vals, options.Values) then ok = false end
      end
      if ok and options.KeyValuePairs ~= nil then
        for k, x in next, options.KeyValuePairs do
          if src[k] ~= x then ok = false end
        end
      end
      if ok and options.Metatable ~= nil and dbg.getmetatable(v) ~= options.Metatable then ok = false end
    end
    if ok then
      if returnOne then return v end
      results[#results + 1] = v
    end
  end
  if returnOne then return nil end
  return results
end)

------------------------------------------------------------------------
-- debug library additions
------------------------------------------------------------------------
local function needLua(f, n, fname)
  if rawtype(f) ~= "function" then argError(n, fname, "function", f) end
  if H.fkind(f) ~= "lua" or isCnative(f) then
    error("invalid argument #" .. n .. " to '" .. fname .. "' (Lua function expected)", 3)
  end
end

def("debug.getconstants", function(f)
  needLua(f, 1, "debug.getconstants")
  return H.consts(f)
end)

def("debug.getconstant", function(f, idx)
  needLua(f, 1, "debug.getconstant")
  if rawtype(idx) ~= "number" then argError(2, "debug.getconstant", "number", idx) end
  local k = H.consts(f)
  if idx < 1 or idx > #k then error("invalid argument #2 to 'debug.getconstant' (constant index out of range)", 2) end
  return k[idx]
end)

def("debug.setconstant", function(f, idx, value)
  needLua(f, 1, "debug.setconstant")
  if rawtype(idx) ~= "number" then argError(2, "debug.setconstant", "number", idx) end
  H.setconst(f, idx, value)
end)

def("debug.getprotos", function(f)
  needLua(f, 1, "debug.getprotos")
  return H.protos(f)
end)

def("debug.getproto", function(f, idx, activated)
  needLua(f, 1, "debug.getproto")
  if rawtype(idx) ~= "number" then argError(2, "debug.getproto", "number", idx) end
  local list = H.protos(f)
  if idx < 1 or idx > #list then error("invalid argument #2 to 'debug.getproto' (proto index out of range)", 2) end
  if activated then return { list[idx] } end
  return list[idx]
end)

local function upIndices(f)
  local list = {}
  local i = 1
  while true do
    local n = dgetup(f, i)
    if n == nil then break end
    if n ~= "_ENV" then list[#list + 1] = i end
    i = i + 1
  end
  return list
end

def("debug.getupvalues", function(f)
  needLua(f, 1, "debug.getupvalues")
  local out = {}
  for k, real in ipairs(upIndices(f)) do
    local _, v = dgetup(f, real)
    out[k] = v
  end
  return out
end)

def("debug.getupvalue", function(f, idx)
  needLua(f, 1, "debug.getupvalue")
  if rawtype(idx) ~= "number" then argError(2, "debug.getupvalue", "number", idx) end
  local real = upIndices(f)[idx]
  if not real then error("invalid argument #2 to 'debug.getupvalue' (upvalue index out of range)", 2) end
  local _, v = dgetup(f, real)
  return v
end)

def("debug.setupvalue", function(f, idx, value)
  needLua(f, 1, "debug.setupvalue")
  if rawtype(idx) ~= "number" then argError(2, "debug.setupvalue", "number", idx) end
  local real = upIndices(f)[idx]
  if not real then error("invalid argument #2 to 'debug.setupvalue' (upvalue index out of range)", 2) end
  dsetup(f, real, value)
end)

def("debug.getstack", function(level, index)
  if rawtype(level) ~= "number" then argError(1, "debug.getstack", "number", level) end
  -- Roblox level 1 = the function that called getstack = level 2 from inside this wrapper
  local lv = level + 1
  if index ~= nil then
    local n, v = dgetlocal(lv, index)
    if n == nil then error("invalid argument #2 to 'debug.getstack' (index out of range)", 2) end
    return v
  end
  local out = {}
  local i = 1
  while true do
    local n, v = dgetlocal(lv, i)
    if n == nil then break end
    out[i] = v
    i = i + 1
  end
  return out
end)

def("debug.setstack", function(level, index, value)
  if rawtype(level) ~= "number" then argError(1, "debug.setstack", "number", level) end
  if rawtype(index) ~= "number" then argError(2, "debug.setstack", "number", index) end
  local n = dsetlocal(level + 1, index, value)
  if n == nil then error("invalid argument #2 to 'debug.setstack' (index out of range)", 2) end
end)

def("debug.getinfo", function(f, what)
  local target = f
  if rawtype(f) == "number" then target = f + 1 end
  local ok, info
  if what ~= nil then ok, info = pcall(dgetinfo, target, what) else ok, info = pcall(dgetinfo, target) end
  if not ok then error("invalid argument #1 to 'debug.getinfo' (function or level expected)", 2) end
  if info and rawtype(f) == "function" then
    info.func = info.func or f
    if H.fkind(f) == "lua" then
      local np, va = H.nparams(f)
      info.numparams = info.numparams or np
      info.is_vararg = info.is_vararg or (va and 1 or 0)
      local n = #upIndices(f)
      info.nups = n
    else
      info.numparams = info.numparams or 0
      info.is_vararg = info.is_vararg or 1
      info.nups = 0
    end
    if info.source == nil then info.source = srcOf(f) end
  end
  return info
end)

------------------------------------------------------------------------
-- profiles (perfect / weak / fake / custom)
------------------------------------------------------------------------
G.__apply_profile = function(profile, disabled)
  if profile == "fake" then
    -- every name exists, nothing really works: this is what sUNC was made to catch
    for name, d in next, DEFS do
      if rawtype(d.value) ~= "table" then
        local stub = H.cwrap(function() end)
        setpath(name, stub)
        for _, a in ipairs(d.aliases) do setpath(a, stub) end
      end
    end
  end
  for _, name in ipairs(disabled or {}) do
    local d = DEFS[name]
    if d then
      setpath(name, nil)
      for _, a in ipairs(d.aliases) do setpath(a, nil) end
    end
  end
end
