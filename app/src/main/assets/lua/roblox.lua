-- roblox.lua : simulated Roblox *client* environment
-- datatypes, signals, Instances + DataModel, services, task scheduler, JSON, require
-- (plain Lua 5.2 for LuaJ)

local H = __host
local G = _G
local rawtype = type
local dbg = debug
local floor, sqrt = math.floor, math.sqrt
if not table.unpack then table.unpack = unpack end
H.rawtype = rawtype

local X = {}          -- shared internals for the executor files
H.X = X

------------------------------------------------------------------------
-- typeof / type
------------------------------------------------------------------------
local function rbxtypeOf(v)
  if rawtype(v) == "table" then
    local mt = dbg.getmetatable(v)
    if mt then return rawget(mt, "__rbxtype") end
  end
  return nil
end

local function typeof(v)
  local r = rbxtypeOf(v)
  if r then return r end
  return rawtype(v)
end

G.typeof = typeof
G.type = function(v)
  if rbxtypeOf(v) then return "userdata" end
  return rawtype(v)
end
X.typeof = typeof

------------------------------------------------------------------------
-- output
------------------------------------------------------------------------
local function joinArgs(...)
  local n = select("#", ...)
  local t = {}
  for i = 1, n do t[i] = tostring((select(i, ...))) end
  return table.concat(t, " ")
end
X.joinArgs = joinArgs

local MessageOut  -- LogService.MessageOut signal (set later)
G.print = function(...)
  local s = joinArgs(...)
  H.log("print", s)
  if MessageOut then X.fire(MessageOut, s, 0) end
end
G.warn = function(...)
  local s = joinArgs(...)
  H.log("warn", s)
  if MessageOut then X.fire(MessageOut, s, 2) end
end
G.printidentity = function() H.log("print", "Current identity is " .. tostring(X.identity)) end

local execName, execVersion, execIdentity = H.exec_info()
X.identity = execIdentity or 8
X.execName = execName
X.execVersion = execVersion

------------------------------------------------------------------------
-- datatypes
------------------------------------------------------------------------
local function newtype(name, methods, getters)
  local mt = { __rbxtype = name }
  mt.__index = function(self, k)
    local m = methods[k]
    if m ~= nil then return m end
    local g = getters and getters[k]
    if g then return g(self) end
    error(tostring(k) .. " is not a valid member of " .. name, 2)
  end
  mt.__newindex = function(_, k) error("Attempt to modify a readonly " .. name .. " (" .. tostring(k) .. ")", 2) end
  return mt
end

-- Vector3 -------------------------------------------------------------
local V3 = {}
local V3m = {}
local V3mt = newtype("Vector3", V3m, {
  Magnitude = function(s) return sqrt(s.X * s.X + s.Y * s.Y + s.Z * s.Z) end,
  Unit = function(s)
    local m = sqrt(s.X * s.X + s.Y * s.Y + s.Z * s.Z)
    if m == 0 then return V3.new(0, 0, 0) end
    return V3.new(s.X / m, s.Y / m, s.Z / m)
  end,
})
function V3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt) end
V3.zero = V3.new(0, 0, 0); V3.one = V3.new(1, 1, 1)
V3.xAxis = V3.new(1, 0, 0); V3.yAxis = V3.new(0, 1, 0); V3.zAxis = V3.new(0, 0, 1)
function V3m.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3m.Cross(a, b)
  return V3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3m.Lerp(a, b, t) return V3.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
function V3m.Abs(a) return V3.new(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
function V3m.FuzzyEq(a, b, e)
  e = e or 1e-5
  return math.abs(a.X - b.X) <= e and math.abs(a.Y - b.Y) <= e and math.abs(a.Z - b.Z) <= e
end
V3mt.__add = function(a, b) return V3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return V3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__mul = function(a, b)
  if rawtype(a) == "number" then return V3.new(a * b.X, a * b.Y, a * b.Z) end
  if rawtype(b) == "number" then return V3.new(a.X * b, a.Y * b, a.Z * b) end
  return V3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
  if rawtype(b) == "number" then return V3.new(a.X / b, a.Y / b, a.Z / b) end
  return V3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__unm = function(a) return V3.new(-a.X, -a.Y, -a.Z) end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return a.X .. ", " .. a.Y .. ", " .. a.Z end

-- Vector2 -------------------------------------------------------------
local V2 = {}
local V2m = {}
local V2mt = newtype("Vector2", V2m, {
  Magnitude = function(s) return sqrt(s.X * s.X + s.Y * s.Y) end,
  Unit = function(s)
    local m = sqrt(s.X * s.X + s.Y * s.Y)
    if m == 0 then return V2.new(0, 0) end
    return V2.new(s.X / m, s.Y / m)
  end,
})
function V2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2mt) end
V2.zero = V2.new(0, 0); V2.one = V2.new(1, 1)
V2.xAxis = V2.new(1, 0); V2.yAxis = V2.new(0, 1)
function V2m.Dot(a, b) return a.X * b.X + a.Y * b.Y end
function V2m.Lerp(a, b, t) return V2.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end
V2mt.__add = function(a, b) return V2.new(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return V2.new(a.X - b.X, a.Y - b.Y) end
V2mt.__mul = function(a, b)
  if rawtype(a) == "number" then return V2.new(a * b.X, a * b.Y) end
  if rawtype(b) == "number" then return V2.new(a.X * b, a.Y * b) end
  return V2.new(a.X * b.X, a.Y * b.Y)
end
V2mt.__div = function(a, b)
  if rawtype(b) == "number" then return V2.new(a.X / b, a.Y / b) end
  return V2.new(a.X / b.X, a.Y / b.Y)
end
V2mt.__unm = function(a) return V2.new(-a.X, -a.Y) end
V2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2mt.__tostring = function(a) return a.X .. ", " .. a.Y end

-- Color3 --------------------------------------------------------------
local C3 = {}
local C3m = {}
local C3mt = newtype("Color3", C3m, {})
function C3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end
function C3.fromRGB(r, g, b) return C3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function C3.fromHSV(h, s, v)
  local i = floor(h * 6)
  local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return C3.new(v, t, p) end
  if i == 1 then return C3.new(q, v, p) end
  if i == 2 then return C3.new(p, v, t) end
  if i == 3 then return C3.new(p, q, v) end
  if i == 4 then return C3.new(t, p, v) end
  return C3.new(v, p, q)
end
function C3.fromHex(hex)
  hex = tostring(hex):gsub("#", "")
  local r = tonumber(hex:sub(1, 2), 16) or 0
  local g = tonumber(hex:sub(3, 4), 16) or 0
  local b = tonumber(hex:sub(5, 6), 16) or 0
  return C3.fromRGB(r, g, b)
end
function C3m.Lerp(a, b, t) return C3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
function C3m.ToHex(a)
  return string.format("%02x%02x%02x", floor(a.R * 255 + 0.5), floor(a.G * 255 + 0.5), floor(a.B * 255 + 0.5))
end
function C3m.ToHSV(a)
  local mx, mn = math.max(a.R, a.G, a.B), math.min(a.R, a.G, a.B)
  local d = mx - mn
  local h = 0
  if d ~= 0 then
    if mx == a.R then h = ((a.G - a.B) / d) % 6
    elseif mx == a.G then h = (a.B - a.R) / d + 2
    else h = (a.R - a.G) / d + 4 end
    h = h / 6
  end
  local s = 0
  if mx ~= 0 then s = d / mx end
  return h, s, mx
end
C3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3mt.__tostring = function(a) return a.R .. ", " .. a.G .. ", " .. a.B end

-- UDim / UDim2 / CFrame / misc ---------------------------------------
local UD = {}
local UDmt = newtype("UDim", {}, {})
function UD.new(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDmt) end
local UD2 = {}
local UD2mt = newtype("UDim2", {}, {})
function UD2.new(xs, xo, ys, yo)
  return setmetatable({ X = UD.new(xs, xo), Y = UD.new(ys, yo), Width = UD.new(xs, xo), Height = UD.new(ys, yo) }, UD2mt)
end
function UD2.fromOffset(x, y) return UD2.new(0, x, 0, y) end
function UD2.fromScale(x, y) return UD2.new(x, 0, y, 0) end

local CF = {}
local CFm = {}
local CFmt = newtype("CFrame", CFm, {})
function CF.new(x, y, z)
  if rawtype(x) == "table" and x.X then x, y, z = x.X, x.Y, x.Z end
  x, y, z = x or 0, y or 0, z or 0
  return setmetatable({ X = x, Y = y, Z = z, Position = V3.new(x, y, z), p = V3.new(x, y, z) }, CFmt)
end
CF.Angles = function() return CF.new(0, 0, 0) end
CF.lookAt = function(at) return CF.new(at) end
CF.identity = CF.new(0, 0, 0)
function CFm.ToWorldSpace(a, b) return CF.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
CFmt.__mul = function(a, b)
  if rbxtypeOf(b) == "Vector3" then return V3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
  return CF.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFmt.__add = function(a, b) return CF.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
CFmt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
CFmt.__tostring = function(a) return a.X .. ", " .. a.Y .. ", " .. a.Z end

local function enumItem(enum, name)
  return { Name = name, Value = 0, EnumType = enum }
end
local EnumMT
EnumMT = {
  __index = function(t, k)
    local e = setmetatable({}, {
      __index = function(t2, k2)
        local it = enumItem(k, k2)
        rawset(t2, k2, it)
        return it
      end,
    })
    rawset(t, k, e)
    return e
  end,
}
local Enum = setmetatable({}, EnumMT)

local function simpleClass(name, ctor)
  local mt = { __rbxtype = name, __tostring = function() return name end }
  mt.__index = {}
  return { new = function(...) return setmetatable(ctor(...), mt) end }
end

local RandomC = {}
function RandomC.new(seed)
  local self = {}
  math.randomseed(seed or os.time())
  function self.NextNumber(_, a, b)
    if a then return a + math.random() * ((b or a) - a) end
    return math.random()
  end
  function self.NextInteger(_, a, b) return math.random(a, b) end
  return setmetatable(self, { __rbxtype = "Random" })
end

local RENV = {}
X.RENV = RENV
local SHARED = {}

local function bakeEnv(env)
  env.Vector3 = V3; env.Vector2 = V2; env.Color3 = C3; env.UDim = UD; env.UDim2 = UD2
  env.CFrame = CF; env.Enum = Enum; env.Random = RandomC
  env.BrickColor = simpleClass("BrickColor", function(n) return { Name = tostring(n or "Medium stone grey") } end)
  env.TweenInfo = simpleClass("TweenInfo", function(t, s, d)
    return { Time = t or 1, EasingStyle = s, EasingDirection = d }
  end)
  env.NumberRange = simpleClass("NumberRange", function(a, b) return { Min = a or 0, Max = b or a or 0 } end)
end
bakeEnv(G)

------------------------------------------------------------------------
-- scheduler + task library
------------------------------------------------------------------------
local Sched = { tasks = {}, current = nil, frameDt = 1 / 60, lastFrame = H.now() }
X.Sched = Sched
local FrameSignals = {}   -- filled once RunService exists
local BoundRender = {}

local function now() return H.now() end

local function addTask(co, cond, deadline)
  Sched.tasks[#Sched.tasks + 1] = { co = co, cond = cond, deadline = deadline }
end

local function resumeCo(co, ...)
  local prev = Sched.current
  Sched.current = co
  local ok, res = coroutine.resume(co, ...)
  Sched.current = prev
  if not ok then
    H.log("error", tostring(res))
  elseif coroutine.status(co) == "suspended" then
    if rawtype(res) == "table" and (res.cond or res.deadline) then
      addTask(co, res.cond, res.deadline)
    else
      addTask(co, nil, now())
    end
  end
end

local function step()
  local t = now()
  local dt = t - Sched.lastFrame
  if dt >= 1 / 60 then
    Sched.lastFrame = t
    for _, name in ipairs({ "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation" }) do
      local sig = FrameSignals[name]
      if sig and #sig.__conns > 0 then X.fire(sig, dt) end
    end
    for _, fn in pairs(BoundRender) do
      local ok, err = pcall(fn, dt)
      if not ok then H.log("error", tostring(err)) end
    end
  end
  local tasks = Sched.tasks
  Sched.tasks = {}
  for i = 1, #tasks do
    local w = tasks[i]
    if w.cancelled or coroutine.status(w.co) == "dead" then
      -- drop
    elseif (w.deadline and t >= w.deadline) or (w.cond and w.cond()) then
      resumeCo(w.co)
    else
      Sched.tasks[#Sched.tasks + 1] = w
    end
  end
end
X.step = step

-- block the current thread until cond() is true / timeout seconds elapse
local function blockUntil(cond, timeout)
  local t0 = now()
  if Sched.current then
    coroutine.yield({ cond = cond, deadline = timeout and (t0 + timeout) or nil })
    return now() - t0
  end
  while true do
    step()
    if cond and cond() then return now() - t0 end
    if timeout and now() - t0 >= timeout then return now() - t0 end
    H.sleep(0.008)
  end
end
X.blockUntil = blockUntil

local function spawnCo(fn, ...)
  local co = coroutine.create(fn)
  X.THREADS[co] = true
  resumeCo(co, ...)
  return co
end

X.THREADS = setmetatable({}, { __mode = "k" })

local task = {}
function task.wait(n)
  n = n or 0.03
  return blockUntil(nil, n)
end
function task.spawn(f, ...)
  if rawtype(f) == "thread" then resumeCo(f, ...); return f end
  return spawnCo(f, ...)
end
function task.defer(f, ...)
  local args = { n = select("#", ...), ... }
  local co = coroutine.create(function() return f(table.unpack(args, 1, args.n)) end)
  X.THREADS[co] = true
  addTask(co, nil, now())
  return co
end
function task.delay(t, f, ...)
  local args = { n = select("#", ...), ... }
  local co = coroutine.create(function() return f(table.unpack(args, 1, args.n)) end)
  X.THREADS[co] = true
  addTask(co, nil, now() + (t or 0))
  return co
end
function task.cancel(co)
  for _, w in ipairs(Sched.tasks) do
    if w.co == co then w.cancelled = true end
  end
end
function task.synchronize() end
function task.desynchronize() end
G.task = task
G.wait = function(n) return task.wait(n), now() end
G.spawn = function(f, ...) return task.spawn(f, ...) end
G.delay = function(t, f, ...) return task.delay(t, f, ...) end
G.tick = function() return H.epoch() end
G.time = function() return now() - X.startTime end
G.elapsedTime = G.time
X.startTime = now()

local ocreate = coroutine.create
coroutine.create = function(f)
  local co = ocreate(f)
  X.THREADS[co] = true
  return co
end

G.__finish = function()
  local started = now()
  local frameWindow = started + 2
  while true do
    local pending = #Sched.tasks
    local frameConns = false
    for _, sig in pairs(FrameSignals) do
      if #sig.__conns > 0 then frameConns = true end
    end
    if pending == 0 and not (frameConns and now() < frameWindow) then break end
    if pending > 0 then frameWindow = now() + 2 end
    if now() - started > 600 then break end
    step()
    H.sleep(0.008)
  end
  H.draw_flush()
end

------------------------------------------------------------------------
-- signals
------------------------------------------------------------------------
local SigM = {}
local SigMT = { __rbxtype = "RBXScriptSignal", __index = SigM, __tostring = function() return "Signal" end }
local ConnM = {}
local ConnMT = { __rbxtype = "RBXScriptConnection", __index = ConnM, __tostring = function() return "Connection" end }

local function newSignal(name)
  return setmetatable({ __conns = {}, __name = name }, SigMT)
end
X.newSignal = newSignal

function SigM.Connect(sig, fn)
  if rawtype(fn) ~= "function" then error("Attempt to connect failed: Passed value is not a function", 2) end
  local rec = { fn = fn, enabled = true, sig = sig, connected = true }
  sig.__conns[#sig.__conns + 1] = rec
  local c = setmetatable({ Connected = true, __rec = rec }, ConnMT)
  rec.handle = c
  return c
end
SigM.connect = SigM.Connect
SigM.ConnectParallel = SigM.Connect
function SigM.Once(sig, fn)
  local c
  c = SigM.Connect(sig, function(...)
    c:Disconnect()
    return fn(...)
  end)
  return c
end
function SigM.Wait(sig)
  local result
  local c
  c = SigM.Connect(sig, function(...)
    result = { n = select("#", ...), ... }
    c:Disconnect()
  end)
  blockUntil(function() return result ~= nil end, nil)
  return table.unpack(result, 1, result.n)
end

local function removeRec(rec)
  rec.connected = false
  if rec.handle then rawset(rec.handle, "Connected", false) end
  local list = rec.sig.__conns
  for i = 1, #list do
    if list[i] == rec then table.remove(list, i); break end
  end
end
X.removeRec = removeRec

function ConnM.Disconnect(c) removeRec(c.__rec) end
ConnM.disconnect = ConnM.Disconnect

local function fire(sig, ...)
  local list = sig.__conns
  local copy = {}
  for i = 1, #list do copy[i] = list[i] end
  for i = 1, #copy do
    local rec = copy[i]
    if rec.connected and rec.enabled and rec.fn then
      local ok, err = pcall(rec.fn, ...)
      if not ok then H.log("error", tostring(err)) end
    end
  end
end
X.fire = fire

------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------
local D = {}            -- proxy -> data
local ALLDATA = {}      -- every data table ever created
X.D = D
X.ALLDATA = ALLDATA

local InstMT = { __rbxtype = "Instance", __metatable = "The metatable is locked" }
X.InstMT = InstMT
local Methods = {}
local CM = {}           -- class specific methods
local NAMECALL = ""
X.getNamecall = function() return NAMECALL end
X.setNamecall = function(n) NAMECALL = n end
local WRAPS = {}

local BASE = {
  Part = "BasePart", MeshPart = "BasePart", WedgePart = "BasePart", SpawnLocation = "BasePart",
  Seat = "BasePart", TrussPart = "BasePart", UnionOperation = "BasePart", Terrain = "BasePart",
  BasePart = "PVInstance", Model = "PVInstance", Tool = "BackpackItem", BackpackItem = "Instance",
  Accessory = "Instance", PVInstance = "Instance",
  Script = "BaseScript", LocalScript = "BaseScript", BaseScript = "LuaSourceContainer",
  ModuleScript = "LuaSourceContainer", LuaSourceContainer = "Instance",
  Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", TextBox = "GuiObject",
  ImageLabel = "GuiObject", ImageButton = "GuiButton", ScrollingFrame = "GuiObject",
  ViewportFrame = "GuiObject", CanvasGroup = "GuiObject", VideoFrame = "GuiObject",
  GuiButton = "GuiObject", GuiObject = "GuiBase2d", GuiBase2d = "GuiBase", GuiBase = "Instance",
  ScreenGui = "LayerCollector", SurfaceGui = "LayerCollector", BillboardGui = "LayerCollector",
  LayerCollector = "GuiBase2d",
  StringValue = "ValueBase", IntValue = "ValueBase", NumberValue = "ValueBase", BoolValue = "ValueBase",
  ObjectValue = "ValueBase", Color3Value = "ValueBase", Vector3Value = "ValueBase", CFrameValue = "ValueBase",
  ValueBase = "Instance",
  Fire = "Instance", Smoke = "Instance", Sparkles = "Instance", Humanoid = "Instance",
  RemoteEvent = "BaseRemoteEvent", BaseRemoteEvent = "Instance", RemoteFunction = "Instance",
  BindableEvent = "Instance", BindableFunction = "Instance",
  ClickDetector = "Instance", ProximityPrompt = "Instance", TouchTransmitter = "Instance",
  Folder = "Instance", Camera = "Instance", Sound = "Instance", Player = "Instance",
  DataModel = "Instance", Workspace = "Model",
  Highlight = "Instance", Attachment = "Instance", Weld = "Instance", WeldConstraint = "Instance",
  Decal = "Instance", Texture = "Instance", SpecialMesh = "Instance", PointLight = "Instance",
  SpotLight = "Instance", ParticleEmitter = "Instance", Beam = "Instance", Trail = "Instance",
  UICorner = "Instance", UIListLayout = "Instance", UIPadding = "Instance", UIStroke = "Instance",
  UIGradient = "Instance", UIScale = "Instance", UIAspectRatioConstraint = "Instance",
  BodyVelocity = "Instance", BodyGyro = "Instance", BodyPosition = "Instance",
  AnimationController = "Instance", Animation = "Instance", Animator = "Instance",
  Configuration = "Instance", Tween = "Instance", Backpack = "Instance",
  PlayerGui = "Instance", PlayerScripts = "Instance", Humanoid_ = "Instance",
}
local SERVICES = {
  "Workspace", "Players", "Lighting", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack",
  "StarterPlayer", "SoundService", "CoreGui", "TeleportService", "HttpService", "RunService",
  "UserInputService", "TweenService", "Debris", "MarketplaceService", "GuiService", "TextService",
  "LogService", "ContentProvider", "VirtualUser", "VirtualInputManager", "CollectionService", "Stats",
  "Chat", "Teams", "TextChatService", "LocalizationService", "ScriptContext", "AssetService",
  "ProximityPromptService", "PathfindingService", "ContextActionService", "HapticService",
  "NetworkClient", "SocialService", "BadgeService", "PolicyService", "InsertService", "Selection",
}
local SERVICESET = {}
for _, n in ipairs(SERVICES) do SERVICESET[n] = true end

local KNOWN = {}
for k, v in pairs(BASE) do KNOWN[k] = true; KNOWN[v] = true end
for _, n in ipairs(SERVICES) do KNOWN[n] = true end
for _, n in ipairs({ "Part", "Model", "Folder", "Weld", "Explosion", "Sky", "Atmosphere", "BloomEffect",
  "BlurEffect", "ColorCorrectionEffect", "SunRaysEffect", "DepthOfFieldEffect", "Clouds", "Hint", "Message",
  "Shirt", "Pants", "BodyColors", "CharacterMesh", "ForceField", "Dialog", "Motor6D", "Rotate", "Hat",
  "RopeConstraint", "SpringConstraint", "HingeConstraint", "BallSocketConstraint", "Constraint" }) do
  KNOWN[n] = true
end
KNOWN.DataModel = nil     -- cannot be created by scripts
for _, n in ipairs(SERVICES) do KNOWN[n] = nil end   -- services cannot be created either

local function isA(cls, target)
  local c = cls
  while c do
    if c == target then return true end
    c = BASE[c]
  end
  return target == "Instance"
end
X.isA = isA

local function chain(cls)
  local list = {}
  local c = cls
  while c do
    table.insert(list, 1, c)
    c = BASE[c]
  end
  if list[1] ~= "Instance" then table.insert(list, 1, "Instance") end
  return list
end

local EVENTS = {
  Instance = { "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying" },
  BasePart = { "Touched", "TouchEnded" },
  ClickDetector = { "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave" },
  ProximityPrompt = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" },
  GuiButton = { "MouseButton1Click", "MouseButton2Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Down", "MouseButton2Up", "Activated" },
  GuiObject = { "MouseEnter", "MouseLeave", "MouseMoved", "InputBegan", "InputEnded", "InputChanged" },
  TextBox = { "FocusLost", "Focused" },
  Humanoid = { "Died", "HealthChanged", "Running", "Jumping", "Seated", "StateChanged" },
  BindableEvent = { "Event" },
  BaseRemoteEvent = { "OnClientEvent" },
  Player = { "CharacterAdded", "CharacterRemoving", "Chatted", "Idled" },
  Players = { "PlayerAdded", "PlayerRemoving" },
  RunService = { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation" },
  UserInputService = { "InputBegan", "InputEnded", "InputChanged", "TextBoxFocused", "TextBoxFocusReleased", "JumpRequest", "WindowFocused", "WindowFocusReleased" },
  LogService = { "MessageOut" },
  ScriptContext = { "Error" },
  Sound = { "Played", "Ended", "Loaded", "Paused", "Resumed" },
  Tween = { "Completed" },
  TeleportService = { "TeleportInitFailed" },
  ProximityPromptService = { "PromptTriggered", "PromptShown", "PromptHidden" },
  GuiService = { "MenuOpened", "MenuClosed" },
}

local Vector3, Color3 = V3, C3
local DEFAULTS = {
  Instance = { Archivable = true },
  BasePart = {
    Anchored = false, CanCollide = true, CanTouch = true, CanQuery = true, Transparency = 0,
    Size = V3.new(4, 1, 2), Position = V3.new(0, 0, 0), Orientation = V3.new(0, 0, 0),
    CFrame = CF.new(0, 0, 0), Color = C3.new(0.63, 0.64, 0.63), Massless = false, Locked = false,
    Material = Enum.Material.Plastic, Reflectance = 0, CastShadow = true,
    AssemblyLinearVelocity = V3.new(0, 0, 0), Velocity = V3.new(0, 0, 0),
  },
  Model = { PrimaryPart = nil },
  LuaSourceContainer = {},
  BaseScript = { Disabled = false, Enabled = true },
  ModuleScript = { Source = "return {}" },
  LocalScript = { Source = "" },
  Script = { Source = "", RunContext = Enum.RunContext.Legacy },
  GuiObject = {
    Visible = true, Size = UD2.new(0, 100, 0, 100), Position = UD2.new(0, 0, 0, 0),
    BackgroundColor3 = C3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 1,
    ZIndex = 1, AnchorPoint = V2.new(0, 0), AbsoluteSize = V2.new(100, 100), AbsolutePosition = V2.new(0, 0),
    Active = false, ClipsDescendants = false, LayoutOrder = 0,
  },
  TextLabel = { Text = "Label", TextColor3 = C3.new(0, 0, 0), TextSize = 14, Font = Enum.Font.SourceSans, TextWrapped = false },
  TextButton = { Text = "Button", TextColor3 = C3.new(0, 0, 0), TextSize = 14, Font = Enum.Font.SourceSans, AutoButtonColor = true },
  TextBox = { Text = "", PlaceholderText = "", TextColor3 = C3.new(0, 0, 0), TextSize = 14, ClearTextOnFocus = true },
  ImageLabel = { Image = "", ImageColor3 = C3.new(1, 1, 1), ImageTransparency = 0 },
  ImageButton = { Image = "", ImageColor3 = C3.new(1, 1, 1), ImageTransparency = 0 },
  LayerCollector = { Enabled = true, ResetOnSpawn = true, DisplayOrder = 0 },
  ScreenGui = { IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
  StringValue = { Value = "" }, IntValue = { Value = 0 }, NumberValue = { Value = 0 },
  BoolValue = { Value = false }, ObjectValue = { Value = nil },
  Color3Value = { Value = C3.new(0, 0, 0) }, Vector3Value = { Value = V3.new(0, 0, 0) },
  Humanoid = {
    Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, HipHeight = 2,
    DisplayName = "", AutoRotate = true, Sit = false, PlatformStand = false, MoveDirection = V3.new(0, 0, 0),
  },
  ClickDetector = { MaxActivationDistance = 32, CursorIcon = "" },
  ProximityPrompt = {
    ActionText = "", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10, Enabled = true,
    RequiresLineOfSight = true, KeyboardKeyCode = Enum.KeyCode.E, ClickablePrompt = true,
  },
  Sound = { SoundId = "", Volume = 0.5, Playing = false, Looped = false, TimePosition = 0, PlaybackSpeed = 1 },
  Camera = { FieldOfView = 70, CFrame = CF.new(0, 10, 10), CameraType = Enum.CameraType.Custom, CameraSubject = nil },
  Workspace = { Gravity = 196.2, CurrentCamera = nil, FilteringEnabled = true },
  Fire = { Color = C3.new(1, 0, 0), SecondaryColor = C3.new(1, 0.5, 0), Enabled = true },
  Smoke = { Color = C3.new(1, 1, 1), Enabled = true },
  Player = { Name = "Player1", DisplayName = "Player1", UserId = 1, AccountAge = 365, Character = nil, Team = nil, CharacterAppearanceId = 1 },
  Tool = { CanBeDropped = true, RequiresHandle = true, Enabled = true },
  RemoteFunction = {}, BindableFunction = {},
  Lighting = { Brightness = 2, ClockTime = 14, FogEnd = 100000, Ambient = C3.new(0.5, 0.5, 0.5), GlobalShadows = true },
  Highlight = { Enabled = true, FillColor = C3.new(1, 0, 0), OutlineColor = C3.new(1, 1, 1), FillTransparency = 0.5, OutlineTransparency = 0 },
  PointLight = { Brightness = 1, Range = 8, Color = C3.new(1, 1, 1), Enabled = true },
  Weld = {}, Beam = {}, Decal = { Texture = "", Transparency = 0 },
}
local HIDDEN = {
  Fire = { size_xml = 5, heat_xml = 9 },
  Smoke = { size_xml = 1, opacity_xml = 0.5, riseVelocity_xml = 1 },
  Player = { SimulationRadius = 1000, MaximumSimulationRadius = 1000 },
  Humanoid = { InternalBodyScale = V3.new(1, 1, 1) },
  Players = { ReplicationFocus = nil },
  Workspace = { InterpolationThrottling = 0 },
}
local CALLBACKS = { RemoteFunction = { "OnClientInvoke" }, BindableFunction = { "OnInvoke" } }

local nextId = 0

local function fullName(d)
  local parts = {}
  local cur = d
  while cur do
    if cur.class == "DataModel" then break end
    table.insert(parts, 1, tostring(cur.props.Name))
    if cur.parent then cur = D[cur.parent] else cur = nil end
  end
  return table.concat(parts, ".")
end
X.fullName = fullName

local function newProxy(d)
  local p = setmetatable({}, InstMT)
  D[p] = d
  d.proxy = p
  return p
end

-- Roblox API dump (Mini-API-Dump.json) support ------------------------
-- The app downloads the dump, converts it to a table and calls __api_apply(tbl).
-- tbl[class] = { s = superclass, c = creatable, v = isService,
--                p = { prop = typeName }, f = { fn = true }, e = { "Event", ... }, d = { prop = default } }
local API = { loaded = false, classes = 0, props = {}, funcs = {} }
X.API = API

G.__api_apply = function(tbl)
  if rawtype(tbl) ~= "table" then return 0 end
  local n = 0
  for name, info in pairs(tbl) do
    n = n + 1
    if info.s and info.s ~= "Object" and info.s ~= "<<<ROOT>>>" and name ~= "Instance" then
      BASE[name] = info.s
    end
    if info.v then
      SERVICESET[name] = true
      KNOWN[name] = nil
    elseif info.c then
      KNOWN[name] = true
    elseif name ~= "Instance" then
      KNOWN[name] = nil
    end
    if info.p then API.props[name] = info.p end
    if info.f then API.funcs[name] = info.f end
    if info.e and #info.e > 0 then
      local cur = EVENTS[name]
      if not cur then cur = {}; EVENTS[name] = cur end
      local have = {}
      for _, e in ipairs(cur) do have[e] = true end
      for _, e in ipairs(info.e) do
        if not have[e] then cur[#cur + 1] = e end
      end
    end
    if info.d then
      local cur = DEFAULTS[name]
      if not cur then cur = {}; DEFAULTS[name] = cur end
      for k, v in pairs(info.d) do
        if cur[k] == nil then cur[k] = v end
      end
    end
  end
  KNOWN.DataModel = nil
  API.loaded = true
  API.classes = n
  return n
end

local API_TYPE_DEFAULT = {
  bool = function() return false end, int = function() return 0 end, float = function() return 0 end,
  double = function() return 0 end, int64 = function() return 0 end, string = function() return "" end,
  Vector3 = function() return V3.new(0, 0, 0) end, Vector2 = function() return V2.new(0, 0) end,
  Color3 = function() return C3.new(0, 0, 0) end, CFrame = function() return CF.new(0, 0, 0) end,
  UDim2 = function() return UD2.new(0, 0, 0, 0) end,
}

local function apiHas(map, cls, key)
  local c = cls
  while c do
    local t = map[c]
    if t and t[key] then return t[key] end
    c = BASE[c]
  end
  return nil
end

if H.api ~= nil then
  local okApi, errApi = pcall(G.__api_apply, H.api)
  if not okApi then H.log("error", "[api dump] " .. tostring(errApi)) end
end

local function createInstance(cls)
  nextId = nextId + 1
  local d = { class = cls, id = nextId, props = {}, children = {}, parent = nil, signals = {}, propsig = {},
    attrs = {}, tags = {}, hprops = {}, scriptable = {}, callbacks = {} }
  for _, c in ipairs(chain(cls)) do
    local def = DEFAULTS[c]
    if def then for k, v in pairs(def) do d.props[k] = v end end
    local ev = EVENTS[c]
    if ev then for _, name in ipairs(ev) do d.signals[name] = newSignal(name) end end
    local hid = HIDDEN[c]
    if hid then for k, v in pairs(hid) do d.hprops[k] = v end end
    local cbs = CALLBACKS[c]
    if cbs then for _, k in ipairs(cbs) do d.callbacks[k] = true end end
  end
  d.props.Name = cls
  ALLDATA[#ALLDATA + 1] = d
  return newProxy(d)
end

local function isInstance(v) return rawtype(v) == "table" and D[v] ~= nil end
X.isInstance = isInstance

local function isDescendantOf(d, ancestor)
  local cur = d.parent
  while cur do
    if cur == ancestor then return true end
    cur = D[cur].parent
  end
  return false
end

local game
local function inGame(d)
  if not game then return false end
  local cur = d.proxy
  while cur do
    if cur == game then return true end
    cur = D[cur].parent
  end
  return false
end
X.inGame = inGame

local ScriptRegistry = {}   -- data tables of script-like instances
X.ScriptRegistry = ScriptRegistry

local function checkLive(d, what)
  if d.destroyed then error("The " .. what .. " property is locked after Destroy()", 3) end
end

local runScriptInstance   -- forward

local function setParent(self, parent)
  local d = D[self]
  if parent ~= nil and not isInstance(parent) then
    error("Unable to assign property Parent. Object expected, got " .. typeof(parent), 3)
  end
  if d.class == "DataModel" then error("Unable to assign property Parent. Property is read only", 3) end
  if d.destroyed and parent ~= nil then error("The Parent property of " .. tostring(d.props.Name) .. " is locked", 3) end
  if parent == self then error("Attempt to set " .. tostring(d.props.Name) .. " as its own parent", 3) end
  local anc = parent
  while anc do
    if anc == self then error("Attempt to set parent of " .. tostring(d.props.Name) .. " would result in a circular reference", 3) end
    anc = D[anc].parent
  end
  local old = d.parent
  if old == parent then return end
  if old then
    local od = D[old]
    for i = 1, #od.children do
      if od.children[i] == d.proxy then table.remove(od.children, i); break end
    end
    X.fire(od.signals.ChildRemoved, d.proxy)
  end
  d.parent = parent
  if parent then
    local pd = D[parent]
    pd.children[#pd.children + 1] = d.proxy
    X.fire(pd.signals.ChildAdded, d.proxy)
    local up = parent
    while up do
      X.fire(D[up].signals.DescendantAdded, d.proxy)
      up = D[up].parent
    end
  end
  X.fire(d.signals.AncestryChanged, d.proxy, parent)
  X.fire(d.signals.Changed, "Parent")
  if d.propsig.Parent then X.fire(d.propsig.Parent) end
  if runScriptInstance then runScriptInstance(d) end
end
X.setParent = setParent

local function wrapMethod(key)
  local w = WRAPS[key]
  if not w then
    w = function(self, ...)
      NAMECALL = key
      return InstMT.__namecall(self, ...)
    end
    WRAPS[key] = w
  end
  return w
end

local function findMethod(d, key)
  local m = Methods[key]
  if m then return m end
  local c = d.class
  while c do
    local t = CM[c]
    if t and t[key] then return t[key] end
    c = BASE[c]
  end
  return nil
end

InstMT.__namecall = function(self, ...)
  local d = D[self]
  if not d then error("Expected ':' not '.' calling member function " .. tostring(NAMECALL), 2) end
  local m = findMethod(d, NAMECALL)
  if not m then
    if API.loaded and apiHas(API.funcs, d.class, NAMECALL) then return nil end
    error(tostring(NAMECALL) .. " is not a valid member of " .. d.class, 2)
  end
  return m(self, ...)
end

InstMT.__index = function(self, key)
  local d = D[self]
  if not d then error("Expected ':' not '.' calling member function", 2) end
  local v = d.props[key]
  if v ~= nil then return v end
  if key == "Parent" then return d.parent end
  if key == "ClassName" then return d.class end
  local s = d.signals[key]
  if s then return s end
  if d.hprops[key] ~= nil then
    if d.scriptable[key] then return d.hprops[key] end
    error(tostring(key) .. " is not a valid member of " .. d.class .. " \"" .. fullName(d) .. "\"", 2)
  end
  if d.callbacks[key] then
    error(tostring(key) .. " is a callback member of " .. d.class .. "; you can only set the callback value, get is not allowed", 2)
  end
  if findMethod(d, key) then return wrapMethod(key) end
  for i = 1, #d.children do
    local c = d.children[i]
    if D[c].props.Name == key then return c end
  end
  if d.extra and d.extra[key] ~= nil then return d.extra[key] end
  if API.loaded then
    local tn = apiHas(API.props, d.class, key)
    if tn then
      local mk = API_TYPE_DEFAULT[tn]
      if mk then return mk() end
      return nil
    end
    if apiHas(API.funcs, d.class, key) then return wrapMethod(key) end
  end
  error(tostring(key) .. " is not a valid member of " .. d.class .. " \"" .. fullName(d) .. "\"", 2)
end

InstMT.__newindex = function(self, key, value)
  local d = D[self]
  if not d then error("invalid instance", 2) end
  if key == "Parent" then setParent(self, value); return end
  if key == "ClassName" then error("Unable to assign property ClassName. Property is read only", 2) end
  if d.callbacks[key] then d.cbvalues = d.cbvalues or {}; d.cbvalues[key] = value; return end
  if d.signals[key] then error("Unable to assign property " .. tostring(key) .. ". Property is read only", 2) end
  if d.hprops[key] ~= nil then
    if not d.scriptable[key] then
      error("Unable to assign property " .. tostring(key) .. ". Property is not scriptable", 2)
    end
    d.hprops[key] = value
    return
  end
  if key == "Name" and rawtype(value) ~= "string" then
    error("Unable to assign property Name. string expected, got " .. typeof(value), 2)
  end
  local old = d.props[key]
  d.props[key] = value
  if old ~= value then
    X.fire(d.signals.Changed, key)
    if d.propsig[key] then X.fire(d.propsig[key]) end
  end
end

InstMT.__tostring = function(self)
  local d = D[self]
  return d and tostring(d.props.Name) or "Instance"
end

-- generic methods -----------------------------------------------------
local function childrenOf(self) return D[self].children end

function Methods.GetChildren(self)
  local out = {}
  for i, c in ipairs(childrenOf(self)) do out[i] = c end
  return out
end
local function descend(self, out)
  for _, c in ipairs(childrenOf(self)) do
    out[#out + 1] = c
    descend(c, out)
  end
end
function Methods.GetDescendants(self)
  local out = {}
  descend(self, out)
  return out
end
function Methods.FindFirstChild(self, name, recursive)
  for _, c in ipairs(childrenOf(self)) do
    if D[c].props.Name == name then return c end
  end
  if recursive then
    for _, c in ipairs(childrenOf(self)) do
      local r = Methods.FindFirstChild(c, name, true)
      if r then return r end
    end
  end
  return nil
end
function Methods.FindFirstChildOfClass(self, cls)
  for _, c in ipairs(childrenOf(self)) do
    if D[c].class == cls then return c end
  end
  return nil
end
function Methods.FindFirstChildWhichIsA(self, cls, recursive)
  for _, c in ipairs(childrenOf(self)) do
    if isA(D[c].class, cls) then return c end
  end
  if recursive then
    for _, c in ipairs(childrenOf(self)) do
      local r = Methods.FindFirstChildWhichIsA(c, cls, true)
      if r then return r end
    end
  end
  return nil
end
function Methods.FindFirstAncestor(self, name)
  local cur = D[self].parent
  while cur do
    if D[cur].props.Name == name then return cur end
    cur = D[cur].parent
  end
  return nil
end
function Methods.FindFirstAncestorOfClass(self, cls)
  local cur = D[self].parent
  while cur do
    if D[cur].class == cls then return cur end
    cur = D[cur].parent
  end
  return nil
end
function Methods.FindFirstAncestorWhichIsA(self, cls)
  local cur = D[self].parent
  while cur do
    if isA(D[cur].class, cls) then return cur end
    cur = D[cur].parent
  end
  return nil
end
function Methods.WaitForChild(self, name, timeout)
  local found = Methods.FindFirstChild(self, name)
  if found then return found end
  blockUntil(function() found = Methods.FindFirstChild(self, name); return found ~= nil end, timeout or 5)
  return found
end
function Methods.IsA(self, cls) return isA(D[self].class, cls) end
function Methods.IsDescendantOf(self, anc) return isDescendantOf(D[self], anc) end
function Methods.IsAncestorOf(self, desc) return isDescendantOf(D[desc], self) end
function Methods.GetFullName(self) return fullName(D[self]) end
function Methods.GetDebugId(self) return "DBG" .. D[self].id end
function Methods.ClearAllChildren(self)
  local list = Methods.GetChildren(self)
  for _, c in ipairs(list) do Methods.Destroy(c) end
end
function Methods.Destroy(self)
  local d = D[self]
  if d.destroyed then return end
  X.fire(d.signals.Destroying)
  Methods.ClearAllChildren(self)
  setParent(self, nil)
  d.destroyed = true
  for _, sig in pairs(d.signals) do
    for i = #sig.__conns, 1, -1 do X.removeRec(sig.__conns[i]) end
  end
  d.running = false
end
Methods.Remove = Methods.Destroy
function Methods.Clone(self)
  local d = D[self]
  if d.props.Archivable == false then return nil end
  local c = createInstance(d.class)
  local cd = D[c]
  for k, v in pairs(d.props) do cd.props[k] = v end
  for k, v in pairs(d.hprops) do cd.hprops[k] = v end
  for k, v in pairs(d.attrs) do cd.attrs[k] = v end
  for _, ch in ipairs(d.children) do
    local cc = Methods.Clone(ch)
    if cc then setParent(cc, c) end
  end
  return c
end
function Methods.GetAttribute(self, name) return D[self].attrs[name] end
function Methods.SetAttribute(self, name, value)
  local d = D[self]
  d.attrs[name] = value
  X.fire(d.signals.Changed, "Attributes")
  if d.attrsig and d.attrsig[name] then X.fire(d.attrsig[name]) end
end
function Methods.GetAttributes(self)
  local out = {}
  for k, v in pairs(D[self].attrs) do out[k] = v end
  return out
end
function Methods.GetPropertyChangedSignal(self, prop)
  local d = D[self]
  local s = d.propsig[prop]
  if not s then s = newSignal(prop); d.propsig[prop] = s end
  return s
end
function Methods.GetAttributeChangedSignal(self, name)
  local d = D[self]
  d.attrsig = d.attrsig or {}
  local s = d.attrsig[name]
  if not s then s = newSignal(name); d.attrsig[name] = s end
  return s
end
function Methods.GetActor() return nil end
function Methods.IsAncestorOfSelf() return false end

-- DataModel methods -------------------------------------------------
CM.DataModel = {}
function CM.DataModel.GetService(self, name)
  local d = D[self]
  for _, c in ipairs(d.children) do
    if D[c].class == name then return c end
  end
  if SERVICESET[name] then
    local s = createInstance(name)
    D[s].isService = true
    setParent(s, self)
    return s
  end
  error("'" .. tostring(name) .. "' is not a valid Service name", 2)
end
CM.DataModel.getService = CM.DataModel.GetService
CM.DataModel.FindService = function(self, name)
  for _, c in ipairs(D[self].children) do
    if D[c].class == name then return c end
  end
  return nil
end
local function httpGet(self, url)
  if rawtype(url) ~= "string" then error("Argument 1 missing or nil", 3) end
  local code, msg, body = H.http("GET", url)
  if code >= 400 then error("HTTP " .. code .. " (" .. msg .. ")", 3) end
  return body
end
CM.DataModel.HttpGet = httpGet
CM.DataModel.HttpGetAsync = httpGet
local function httpPost(self, url, data, ctype)
  local code, msg, body = H.http("POST", url, { ["Content-Type"] = ctype or "application/json" }, data)
  if code >= 400 then error("HTTP " .. code .. " (" .. msg .. ")", 3) end
  return body
end
CM.DataModel.HttpPost = httpPost
CM.DataModel.HttpPostAsync = httpPost
CM.DataModel.GetObjects = function() return {} end
CM.DataModel.BindToClose = function() end
CM.DataModel.IsLoaded = function() return true end

------------------------------------------------------------------------
-- Instance.new + game tree
------------------------------------------------------------------------
local Instance = {}
function Instance.new(cls, parent)
  if rawtype(cls) ~= "string" or not KNOWN[cls] then
    error("Unable to create an Instance of type \"" .. tostring(cls) .. "\"", 2)
  end
  local inst = createInstance(cls)
  if parent ~= nil then setParent(inst, parent) end
  return inst
end
G.Instance = Instance

local function mk(cls, name, parent)
  local i = createInstance(cls)
  if name then D[i].props.Name = name end
  if parent then setParent(i, parent) end
  return i
end

game = createInstance("DataModel")
D[game].props.Name = "Game"
D[game].props.PlaceId = 1818
D[game].props.GameId = 1818
D[game].props.PlaceVersion = 1
D[game].props.JobId = "00000000-0000-0000-0000-000000000000"
D[game].props.CreatorId = 1
D[game].props.CreatorType = Enum.CreatorType.User
X.game = game

local GetService = CM.DataModel.GetService
local workspace = GetService(game, "Workspace")
local Players = GetService(game, "Players")
local Lighting = GetService(game, "Lighting")
local ReplicatedStorage = GetService(game, "ReplicatedStorage")
local CoreGui = GetService(game, "CoreGui")
local RunService = GetService(game, "RunService")
local LogService = GetService(game, "LogService")
local ScriptContext = GetService(game, "ScriptContext")
GetService(game, "ReplicatedFirst"); GetService(game, "StarterGui"); GetService(game, "StarterPack")
GetService(game, "StarterPlayer"); GetService(game, "SoundService"); GetService(game, "HttpService")
GetService(game, "UserInputService"); GetService(game, "TweenService"); GetService(game, "TeleportService")
GetService(game, "Debris"); GetService(game, "MarketplaceService"); GetService(game, "GuiService")
GetService(game, "CollectionService"); GetService(game, "TextService"); GetService(game, "ContentProvider")
GetService(game, "VirtualUser"); GetService(game, "VirtualInputManager"); GetService(game, "Stats")
GetService(game, "ProximityPromptService"); GetService(game, "Chat"); GetService(game, "Teams")
GetService(game, "TextChatService"); GetService(game, "ContextActionService")
X.workspace = workspace
MessageOut = D[LogService].signals.MessageOut
X.MessageOut = MessageOut
X.RunService = RunService
for _, n in ipairs({ "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation" }) do
  FrameSignals[n] = D[RunService].signals[n]
end

-- world
local camera = mk("Camera", "Camera", workspace)
D[workspace].props.CurrentCamera = camera
mk("Terrain", "Terrain", workspace)
local base = mk("Part", "Baseplate", workspace)
D[base].props.Anchored = true
D[base].props.Size = V3.new(512, 20, 512)
D[base].props.Position = V3.new(0, -10, 0)
local spawn = mk("SpawnLocation", "SpawnLocation", workspace)
D[spawn].props.Position = V3.new(0, 1, 0)

local lp = mk("Player", "Player1", Players)
D[Players].props.LocalPlayer = lp
X.localPlayer = lp
D[Players].props.MaxPlayers = 12
D[lp].props.Name = "Player1"
local char = mk("Model", "Player1", workspace)
local hrp = mk("Part", "HumanoidRootPart", char)
D[hrp].props.Size = V3.new(2, 2, 1)
D[hrp].props.Position = V3.new(0, 3, 0)
local head = mk("Part", "Head", char)
D[head].props.Position = V3.new(0, 4.5, 0)
local hum = mk("Humanoid", "Humanoid", char)
D[char].props.PrimaryPart = hrp
D[lp].props.Character = char
mk("Backpack", "Backpack", lp)
local pg = mk("PlayerGui", "PlayerGui", lp)
mk("ScreenGui", "MainGui", pg)
local ps = mk("PlayerScripts", "PlayerScripts", lp)
-- idled has a native (foreign) connection like in the real client
D[lp].signals.Idled.__conns[1] = { enabled = true, connected = true, foreign = true, sig = D[lp].signals.Idled }
D[ScriptContext].signals.Error.__conns[1] = { enabled = true, connected = true, foreign = true, sig = D[ScriptContext].signals.Error }

local hui = mk("Folder", "HiddenUI", CoreGui)
mk("ScreenGui", "RobloxGui", CoreGui)
X.hui = hui

-- default scripts the real client always has
local function mkscript(cls, name, parent, src)
  local s = mk(cls, name, nil)
  D[s].props.Source = src
  D[s].ran = true
  setParent(s, parent)
  return s
end
local psl = mkscript("LocalScript", "PlayerScriptsLoader", ps, "local Players = game:GetService('Players')\nlocal pm = require(script.Parent:WaitForChild('PlayerModule'))\nprint('loader')")
local pmod = mkscript("ModuleScript", "PlayerModule", ps, "local M = {}\nfunction M:GetCameras() return {} end\nfunction M:GetControls() return {} end\nreturn M")
local cammod = mkscript("ModuleScript", "CameraModule", pmod, "return { Enabled = true }")
local ctlmod = mkscript("ModuleScript", "ControlModule", pmod, "return { Enabled = true }")
local animate = mkscript("LocalScript", "Animate", char, "-- character animation controller\nlocal Figure = script.Parent")
local sounds = mkscript("LocalScript", "RbxCharacterSounds", char, "-- character sounds")

------------------------------------------------------------------------
-- class specific methods
------------------------------------------------------------------------
CM.Players = {
  GetPlayers = function() return { lp } end,
  GetPlayerFromCharacter = function(_, c) if c == char then return lp end return nil end,
  GetPlayerByUserId = function(_, id) if id == 1 then return lp end return nil end,
  GetNameFromUserIdAsync = function() return "Player1" end,
  GetUserIdFromNameAsync = function() return 1 end,
}
CM.Player = {
  Kick = function(_, msg) H.log("warn", "[Kick] " .. tostring(msg or "")) end,
  GetMouse = function()
    local m = { X = 0, Y = 0, Hit = CF.new(0, 0, 0), Target = nil, UnitRay = {}, Button1Down = newSignal("Button1Down"),
      Button1Up = newSignal("Button1Up"), Move = newSignal("Move"), KeyDown = newSignal("KeyDown"), KeyUp = newSignal("KeyUp") }
    local x, y = H.cursor()
    m.X, m.Y = x, y
    return m
  end,
  LoadCharacter = function() end,
  ClearCharacterAppearance = function() end,
  IsFriendsWith = function() return false end,
  GetRankInGroup = function() return 0 end,
}
CM.Humanoid = {
  TakeDamage = function(self, n) local d = D[self]; d.props.Health = math.max(0, d.props.Health - n) end,
  GetState = function() return Enum.HumanoidStateType.Running end,
  ChangeState = function() end,
  MoveTo = function() end,
  Move = function() end,
  EquipTool = function() end,
  UnequipTools = function() end,
  GetAccessories = function() return {} end,
}
CM.Workspace = {
  Raycast = function() return nil end,
  GetServerTimeNow = function() return H.epoch() end,
  GetPartBoundsInBox = function() return {} end,
  GetPartBoundsInRadius = function() return {} end,
  FindPartOnRay = function() return nil, V3.new(0, 0, 0) end,
}
CM.Model = {
  GetPivot = function(self) return D[self].props.CFrame or CF.new(0, 0, 0) end,
  PivotTo = function(self, cf) D[self].props.CFrame = cf end,
  MoveTo = function() end,
  GetBoundingBox = function() return CF.new(0, 0, 0), V3.new(4, 4, 4) end,
  GetExtentsSize = function() return V3.new(4, 4, 4) end,
}
CM.BasePart = {
  GetMass = function() return 1 end,
  GetTouchingParts = function() return {} end,
  SetNetworkOwner = function() end,
  GetNetworkOwner = function() return nil end,
  GetPivot = function(self) return D[self].props.CFrame end,
  PivotTo = function(self, cf) D[self].props.CFrame = cf end,
  IsGrounded = function() return true end,
}
CM.RunService = {
  IsClient = function() return true end,
  IsServer = function() return false end,
  IsStudio = function() return false end,
  IsRunning = function() return true end,
  IsRunMode = function() return false end,
  IsEdit = function() return false end,
  BindToRenderStep = function(_, name, _, fn) BoundRender[name] = fn end,
  UnbindFromRenderStep = function(_, name) BoundRender[name] = nil end,
}
CM.BindableEvent = {
  Fire = function(self, ...) X.fire(D[self].signals.Event, ...) end,
}
CM.BaseRemoteEvent = {
  FireServer = function() end,
}
CM.RemoteFunction = {
  InvokeServer = function() return nil end,
}
CM.BindableFunction = {
  Invoke = function(self, ...)
    local f = D[self].cbvalues and D[self].cbvalues.OnInvoke
    if f then return f(...) end
    return nil
  end,
}
CM.ClickDetector = {}
CM.ProximityPrompt = {
  InputHoldBegin = function() end,
  InputHoldEnd = function() end,
}
CM.StarterGui = {
  SetCore = function(_, n, v) H.log("info", "[SetCore] " .. tostring(n)) end,
  GetCore = function() return nil end,
  SetCoreGuiEnabled = function() end,
  GetCoreGuiEnabled = function() return true end,
}
CM.Sound = {
  Play = function(self) D[self].props.Playing = true end,
  Stop = function(self) D[self].props.Playing = false end,
  Pause = function(self) D[self].props.Playing = false end,
  Resume = function(self) D[self].props.Playing = true end,
}
CM.TextService = {
  GetTextSize = function(_, text, size) return V2.new(#tostring(text) * size * 0.5, size) end,
}
CM.GuiService = {
  GetGuiInset = function() return V2.new(0, 36), V2.new(0, 0) end,
  IsTenFootInterface = function() return false end,
}
CM.ContentProvider = {
  PreloadAsync = function() end,
  GetAssetFetchStatus = function() return Enum.AssetFetchStatus.Success end,
}
CM.LogService = {
  GetLogHistory = function() return {} end,
}
CM.MarketplaceService = {
  GetProductInfo = function(_, id)
    return { Name = "Simulated Asset " .. tostring(id), Description = "ExecSim", AssetId = id, ProductId = id,
      PriceInRobux = 0, Creator = { Name = "ExecSim", Id = 1 } }
  end,
  UserOwnsGamePassAsync = function() return false end,
  PromptPurchase = function() end,
}
CM.Debris = {
  AddItem = function(_, inst, t)
    task.delay(t or 10, function() if inst and D[inst] and not D[inst].destroyed then Methods.Destroy(inst) end end)
  end,
}
CM.CollectionService = {
  AddTag = function(_, inst, tag) D[inst].tags[tag] = true end,
  RemoveTag = function(_, inst, tag) D[inst].tags[tag] = nil end,
  HasTag = function(_, inst, tag) return D[inst].tags[tag] == true end,
  GetTags = function(_, inst) local o = {}; for k in pairs(D[inst].tags) do o[#o + 1] = k end; return o end,
  GetTagged = function(_, tag)
    local o = {}
    for _, d in ipairs(ALLDATA) do
      if d.tags[tag] and not d.destroyed then o[#o + 1] = d.proxy end
    end
    return o
  end,
}
CM.VirtualUser = {
  CaptureController = function() end,
  ClickButton1 = function() H.input("click", 1) end,
  ClickButton2 = function() H.input("click", 2) end,
  Button1Down = function() H.input("press", 1) end,
  Button1Up = function() H.input("release", 1) end,
  Button2Down = function() H.input("press", 2) end,
  Button2Up = function() H.input("release", 2) end,
  SetKeyDown = function() end,
  SetKeyUp = function() end,
  TypeKey = function() end,
}
CM.VirtualInputManager = {
  SendKeyEvent = function() end,
  SendMouseButtonEvent = function(_, x, y, btn, down)
    H.input("move_abs", x, y)
    H.input(down and "press" or "release", (btn or 0) + 1)
  end,
  SendMouseMoveEvent = function(_, x, y) H.input("move_abs", x, y) end,
  SendMouseWheelEvent = function() end,
  SendTouchEvent = function() end,
}
CM.UserInputService = {
  GetMouseLocation = function() local x, y = H.cursor(); return V2.new(x, y) end,
  GetMouseDelta = function() return V2.new(0, 0) end,
  IsKeyDown = function() return false end,
  IsMouseButtonPressed = function() return false end,
  GetFocusedTextBox = function() return nil end,
  GetKeysPressed = function() return {} end,
  GetLastInputType = function() return Enum.UserInputType.Keyboard end,
  GetPlatform = function() return Enum.Platform.Windows end,
  GetStringForKeyCode = function(_, k) return tostring(k and k.Name or "") end,
}
D[GetService(game, "UserInputService")].props.MouseEnabled = true
D[GetService(game, "UserInputService")].props.KeyboardEnabled = true
D[GetService(game, "UserInputService")].props.TouchEnabled = false
D[GetService(game, "UserInputService")].props.GamepadEnabled = false
D[GetService(game, "UserInputService")].props.MouseBehavior = Enum.MouseBehavior.Default
D[GetService(game, "UserInputService")].props.MouseIconEnabled = true
CM.ContextActionService = {
  BindAction = function() end, UnbindAction = function() end,
}
CM.ProximityPromptService = {}
CM.TeleportService = {
  Teleport = function(_, id)
    H.log("info", "[TeleportService] teleporting to " .. tostring(id))
    X.runTeleportQueue()
  end,
  TeleportToPlaceInstance = function(_, id)
    H.log("info", "[TeleportService] teleporting to " .. tostring(id))
    X.runTeleportQueue()
  end,
  GetLocalPlayerTeleportData = function() return nil end,
}
CM.TweenService = {
  Create = function(_, inst, info, goal)
    local tw = createInstance("Tween")
    D[tw].props.PlaybackState = Enum.PlaybackState.Begin
    local d = D[tw]
    d.extra = {
      Play = function()
        for k, v in pairs(goal) do inst[k] = v end
        task.delay(info and info.Time or 0, function()
          X.fire(d.signals.Completed, Enum.PlaybackState.Completed)
        end)
      end,
      Pause = function() end,
      Cancel = function() end,
    }
    return tw
  end,
}
CM.Tween = {
  Play = function(self) D[self].extra.Play() end,
  Pause = function() end,
  Cancel = function() end,
}

-- queue_on_teleport support
X.teleportQueue = {}
function X.runTeleportQueue()
  local q = X.teleportQueue
  X.teleportQueue = {}
  for _, code in ipairs(q) do
    local fn, err = load(H.luau(code), "executor")
    if fn then
      local ok, e = pcall(fn)
      if not ok then H.log("error", tostring(e)) end
    else
      H.log("error", tostring(err))
    end
  end
end

------------------------------------------------------------------------
-- HttpService + JSON
------------------------------------------------------------------------
local function jsonEscape(s)
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end)
  return s
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

local function jsonEncode(v, depth)
  depth = depth or 0
  if depth > 100 then error("JSON nesting too deep") end
  local t = rawtype(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("Cannot convert number to JSON") end
    if v == floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return tostring(v)
  end
  if t == "string" then return '"' .. jsonEscape(v) .. '"' end
  if t == "table" then
    local parts = {}
    if isArray(v) then
      for i = 1, #v do parts[i] = jsonEncode(v[i], depth + 1) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, val in pairs(v) do
      parts[#parts + 1] = '"' .. jsonEscape(tostring(k)) .. '":' .. jsonEncode(val, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("Cannot convert " .. t .. " to JSON")
end

local function jsonDecode(str)
  local pos = 1
  local function ws() pos = str:find("%S", pos) or (#str + 1) end
  local value
  local function err(msg) error("Can't parse JSON: " .. msg .. " at position " .. pos, 0) end
  local function parseString()
    pos = pos + 1
    local out = {}
    while true do
      local c = str:sub(pos, pos)
      if c == "" then err("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = str:sub(pos + 1, pos + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
        if n == "u" then
          local code = tonumber(str:sub(pos + 2, pos + 5), 16) or 63
          out[#out + 1] = code < 128 and string.char(code) or "?"
          pos = pos + 6
        else
          out[#out + 1] = map[n] or n
          pos = pos + 2
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = str:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      ws()
      if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws()
        if str:sub(pos, pos) ~= '"' then err("expected string key") end
        local k = parseString()
        ws()
        if str:sub(pos, pos) ~= ":" then err("expected ':'") end
        pos = pos + 1
        obj[k] = value()
        ws()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == "}" then break end
        if d ~= "," then err("expected ',' or '}'") end
      end
      return obj
    elseif c == "[" then
      pos = pos + 1
      local arr = {}
      ws()
      if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value()
        ws()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == "]" then break end
        if d ~= "," then err("expected ',' or ']'") end
      end
      return arr
    elseif c == '"' then
      return parseString()
    elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
      if not num or num == "" then err("unexpected character") end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local r = value()
  ws()
  if pos <= #str then err("trailing characters") end
  return r
end
X.jsonEncode, X.jsonDecode = jsonEncode, jsonDecode

local function guid()
  local t = {}
  for i = 1, 16 do t[i] = string.format("%02X", math.random(0, 255)) end
  local s = table.concat(t)
  return "{" .. s:sub(1, 8) .. "-" .. s:sub(9, 12) .. "-" .. s:sub(13, 16) .. "-" .. s:sub(17, 20) .. "-" .. s:sub(21, 32) .. "}"
end

CM.HttpService = {
  JSONEncode = function(_, v) return jsonEncode(v) end,
  JSONDecode = function(_, s) return jsonDecode(s) end,
  GenerateGUID = function(_, wrap)
    local g = guid()
    if wrap == false then g = g:sub(2, -2) end
    return g
  end,
  UrlEncode = function(_, s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
  end,
  GetAsync = function(self, url) return httpGet(self, url) end,
  PostAsync = function(self, url, data, ct) return httpPost(self, url, data, ct) end,
  RequestAsync = function(_, opts)
    if rawtype(opts) ~= "table" or rawtype(opts.Url) ~= "string" then error("Url is required", 2) end
    local code, msg, body, headers = H.http(opts.Method or "GET", opts.Url, opts.Headers, opts.Body)
    return { Success = code >= 200 and code < 300, StatusCode = code, StatusMessage = msg, Headers = headers, Body = body }
  end,
}
D[GetService(game, "HttpService")].props.HttpEnabled = true

------------------------------------------------------------------------
-- running game scripts (require / LocalScript on parent)
------------------------------------------------------------------------
X.callerGame = 0
X.currentScript = nil

local function scriptEnv(inst)
  local env = setmetatable({ script = inst }, { __index = RENV })
  return env
end
X.scriptEnv = scriptEnv

local function compileScript(inst)
  local d = D[inst]
  local env = d.env or scriptEnv(inst)
  d.env = env
  local fn, err = load(H.luau(tostring(d.props.Source or "")), "game_script:" .. fullName(d), "t", env)
  if not fn then error(err, 0) end
  return fn, env
end
X.compileScript = compileScript

G.require = function(m)
  if not isInstance(m) or not isA(D[m].class, "ModuleScript") then
    error("Attempted to call require with invalid argument(s).", 2)
  end
  local d = D[m]
  if d.loaded then return d.result end
  local fn = compileScript(m)
  X.callerGame = X.callerGame + 1
  local saved = X.currentScript
  X.currentScript = m
  local ok, res = pcall(fn)
  X.currentScript = saved
  X.callerGame = X.callerGame - 1
  if not ok then error(res, 0) end
  d.loaded = true
  d.result = res
  return res
end

runScriptInstance = function(d)
  if d.class ~= "LocalScript" then return end
  if d.ran or d.destroyed then return end
  if d.props.Disabled or d.props.Enabled == false then return end
  if not inGame(d) then return end
  d.ran = true
  d.running = true
  if tostring(d.props.Source or "") == "" then return end
  local okc, fn = pcall(compileScript, d.proxy)
  if not okc then H.log("error", tostring(fn)); return end
  local co = coroutine.create(function()
    X.callerGame = X.callerGame + 1
    local saved = X.currentScript
    X.currentScript = d.proxy
    local ok, e = pcall(fn)
    X.currentScript = saved
    X.callerGame = X.callerGame - 1
    if not ok then H.log("error", tostring(e)) end
  end)
  X.THREADS[co] = true
  d.thread = co
  resumeCo(co)
end

-- default scripts count as running / loaded
for _, s in ipairs({ psl, animate, sounds }) do
  local d = D[s]
  d.running = true
  d.ran = true
  d.env = scriptEnv(s)
  d.thread = coroutine.create(function() end)
  X.THREADS[d.thread] = true
end
for _, s in ipairs({ pmod, cammod, ctlmod }) do
  local d = D[s]
  d.loaded = true
  d.result = { Enabled = true }
  d.env = scriptEnv(s)
end

-- register script-class instances on creation (by wrapping createInstance users)
local origNew = Instance.new
function Instance.new(cls, parent)
  local inst = origNew(cls, parent)
  return inst
end

------------------------------------------------------------------------
-- globals exported to scripts
------------------------------------------------------------------------
G.game = game
G.workspace = workspace
G.Workspace = workspace
G.script = nil
G.shared = {}
G.Game = game

-- Roblox env (getrenv)
for k, v in pairs(G) do
  if rawtype(k) == "string" and k ~= "debug" and k:sub(1, 2) ~= "__" then RENV[k] = v end
end
RENV._G = SHARED
RENV.debug = { traceback = dbg.traceback, getinfo = dbg.getinfo }
X.SHARED = SHARED
