-- unc_drawing.lua : Drawing library + render-object functions
-- Every property change is mirrored to the Android "Screen" tab through __host.draw_*

local H = __host
local G = _G
local X = H.X
local rawtype = H.rawtype
local def = X.def
local argError = X.argError
local typeof = X.typeof

local black = G.Color3.new(0, 0, 0)
local white = G.Color3.new(1, 1, 1)
local V2 = G.Vector2

local FONTS = { UI = 0, System = 1, Plex = 2, Monospace = 3 }

local function common(extra)
  local t = { Visible = false, Transparency = 1, ZIndex = 0, Color = black }
  for k, v in pairs(extra) do t[k] = v end
  return t
end

local SCHEMA = {
  Line = function()
    return common({ Thickness = 1, From = V2.new(0, 0), To = V2.new(0, 0) })
  end,
  Text = function()
    return common({
      Text = "", Size = 14, Center = false, Outline = false, OutlineColor = black,
      Position = V2.new(0, 0), Font = FONTS.UI, TextBounds = V2.new(0, 0),
    })
  end,
  Image = function()
    return common({
      Data = "", Uri = "", Size = V2.new(0, 0), Position = V2.new(0, 0), Rounding = 0, Color = white,
    })
  end,
  Circle = function()
    return common({ Thickness = 1, NumSides = 0, Radius = 0, Position = V2.new(0, 0), Filled = false })
  end,
  Square = function()
    return common({ Thickness = 1, Size = V2.new(0, 0), Position = V2.new(0, 0), Filled = false })
  end,
  Quad = function()
    return common({
      Thickness = 1, PointA = V2.new(0, 0), PointB = V2.new(0, 0), PointC = V2.new(0, 0),
      PointD = V2.new(0, 0), Filled = false,
    })
  end,
  Triangle = function()
    return common({
      Thickness = 1, PointA = V2.new(0, 0), PointB = V2.new(0, 0), PointC = V2.new(0, 0), Filled = false,
    })
  end,
}

local READONLY = { TextBounds = true }
local STORE = {}     -- object -> { id, type, props, removed }
local nextId = 0

local function push(id, key, value)
  local t = typeof(value)
  if t == "Vector2" then
    H.draw_set(id, key, value.X, value.Y)
  elseif t == "Color3" then
    H.draw_set(id, key, value.R, value.G, value.B)
  elseif t == "number" or t == "boolean" or t == "string" then
    H.draw_set(id, key, value)
  end
end

local function refreshBounds(st)
  if st.type == "Text" then
    local size = st.props.Size or 14
    st.props.TextBounds = V2.new(#tostring(st.props.Text) * size * 0.5, size)
  end
end

local function setProp(obj, key, value)
  local st = STORE[obj]
  if not st then error("invalid argument #1 (render object expected)", 3) end
  if st.removed then error("Render object has been removed", 3) end
  if st.props[key] == nil then error("'" .. tostring(key) .. "' is not a valid property of " .. st.type, 3) end
  if READONLY[key] then error("'" .. tostring(key) .. "' is read only", 3) end
  st.props[key] = value
  push(st.id, key, value)
  if key == "Text" or key == "Size" then
    refreshBounds(st)
  end
end

local function getProp(obj, key)
  local st = STORE[obj]
  if not st then error("invalid argument #1 (render object expected)", 3) end
  local v = st.props[key]
  if v == nil then error("'" .. tostring(key) .. "' is not a valid property of " .. st.type, 3) end
  return v
end

local function remove(obj)
  local st = STORE[obj]
  if st and not st.removed then
    st.removed = true
    H.draw_del(st.id)
  end
end

local ObjMT = { __rbxtype = "userdata" }
ObjMT.__index = function(obj, key)
  if key == "Remove" or key == "Destroy" then return remove end
  return getProp(obj, key)
end
ObjMT.__newindex = function(obj, key, value) setProp(obj, key, value) end
ObjMT.__tostring = function(obj)
  local st = STORE[obj]
  return "Drawing(" .. (st and st.type or "?") .. ")"
end

local Drawing = {}
def("Drawing", Drawing)

def("Drawing.Fonts", FONTS)

def("Drawing.new", function(kind)
  if rawtype(kind) ~= "string" then argError(1, "Drawing.new", "string", kind) end
  local schema = SCHEMA[kind]
  if not schema then error("invalid argument #1 to 'Drawing.new' (invalid drawing type '" .. kind .. "')", 2) end
  nextId = nextId + 1
  local obj = setmetatable({}, ObjMT)
  local st = { id = nextId, type = kind, props = schema(), removed = false }
  STORE[obj] = st
  H.draw_new(st.id, kind)
  for k, v in pairs(st.props) do push(st.id, k, v) end
  return obj
end)

def("isrenderobj", function(obj)
  return rawtype(obj) == "table" and STORE[obj] ~= nil and not STORE[obj].removed
end)

def("getrenderproperty", function(obj, key)
  if rawtype(obj) ~= "table" or not STORE[obj] then argError(1, "getrenderproperty", "render object", obj) end
  if rawtype(key) ~= "string" then argError(2, "getrenderproperty", "string", key) end
  return getProp(obj, key)
end)

def("setrenderproperty", function(obj, key, value)
  if rawtype(obj) ~= "table" or not STORE[obj] then argError(1, "setrenderproperty", "render object", obj) end
  if rawtype(key) ~= "string" then argError(2, "setrenderproperty", "string", key) end
  setProp(obj, key, value)
end)

def("cleardrawcache", function()
  for _, st in pairs(STORE) do st.removed = true end
  STORE = {}
  H.draw_clear()
end)
