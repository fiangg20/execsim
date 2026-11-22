-- world.lua : simulated Roblox *world* on top of roblox.lua
-- gravity + collisions, Humanoid (walk / jump / health / death / respawn), Touched, Raycast,
-- spatial queries, Camera, Model pivots, and the snapshot functions used by the Game tab.
-- (plain Lua 5.2 for LuaJ, no goto)

local H = __host
local G = _G
local X = H.X
local rawtype = H.rawtype
local D = X.D
local V3, V2, C3, CF = X.V3, X.V2, X.C3, X.CF
local CFmath = X.CFmath
local CM, Methods, mk = X.CM, X.Methods, X.mk
local isA = X.isA
local abs, sqrt, floor, min, max = math.abs, math.sqrt, math.floor, math.min, math.max
local sin, cos, rad, deg = math.sin, math.cos, math.rad, math.deg
local atan2 = math.atan2 or math.atan
local Enum = G.Enum

local workspace = X.workspace
local wsD = D[workspace]
local camera = X.camera
local camD = D[camera]
local charModel = X.char
local hrpP, humP = X.hrp, X.hum
local hrpD, humD = D[hrpP], D[humP]
local lpD = D[X.localPlayer]
local HK = X.PropHooks

local function now() return H.now() end

------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------
local function isPartData(d) return isA(d.class, "BasePart") end

local function setCF(d, cf)
  d.props.CFrame = cf
  d.props.Position = V3.new(cf.X, cf.Y, cf.Z)
  local rx, ry, rz = cf:ToOrientation()
  d.props.Orientation = V3.new(deg(rx), deg(ry), deg(rz))
  if d.propsig.CFrame then X.fire(d.propsig.CFrame) end
  if d.propsig.Position then X.fire(d.propsig.Position) end
end

local function validCF(cf)
  return rawtype(cf) == "table" and cf.R00 ~= nil
end

-- axis aligned bounding box of a part (cached on the CFrame / Size identity)
local function bbOf(d)
  local cf, sz = d.props.CFrame, d.props.Size
  local bb = d.bb
  if bb and bb.cf == cf and bb.sz == sz then return bb end
  if not validCF(cf) or rawtype(sz) ~= "table" or sz.X == nil then return nil end
  local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
  local ex = abs(cf.R00) * hx + abs(cf.R01) * hy + abs(cf.R02) * hz
  local ey = abs(cf.R10) * hx + abs(cf.R11) * hy + abs(cf.R12) * hz
  local ez = abs(cf.R20) * hx + abs(cf.R21) * hy + abs(cf.R22) * hz
  bb = { cf = cf, sz = sz, ex = ex, ey = ey, ez = ez,
    x0 = cf.X - ex, x1 = cf.X + ex, y0 = cf.Y - ey, y1 = cf.Y + ey, z0 = cf.Z - ez, z1 = cf.Z + ez }
  d.bb = bb
  return bb
end

local function overlap(a, b, pad)
  pad = pad or 0
  return a.x0 - pad < b.x1 and a.x1 + pad > b.x0 and a.y0 - pad < b.y1 and a.y1 + pad > b.y0
    and a.z0 - pad < b.z1 and a.z1 + pad > b.z0
end

local function gather(d, out)
  local ch = d.children
  for i = 1, #ch do
    local cd = D[ch[i]]
    if cd then
      if isPartData(cd) and cd.class ~= "Terrain" then out[#out + 1] = cd end
      if #cd.children > 0 then gather(cd, out) end
    end
  end
end

local function allParts()
  local out = {}
  gather(wsD, out)
  return out
end

local function wake(d)
  if d.phys then d.phys.rest = false end
end

------------------------------------------------------------------------
-- property hooks (Position / CFrame / Orientation stay in sync, Health rules, velocity)
------------------------------------------------------------------------
HK.Position = function(d, v)
  if not isPartData(d) or rawtype(v) ~= "table" or v.X == nil then return end
  local cf = d.props.CFrame
  local rot = validCF(cf) and cf.Rotation or CF.new()
  local ncf = CF.new(v.X, v.Y, v.Z) * rot
  d.props.CFrame = ncf
  local rx, ry, rz = ncf:ToOrientation()
  d.props.Orientation = V3.new(deg(rx), deg(ry), deg(rz))
  wake(d)
end

HK.CFrame = function(d, v)
  if not isPartData(d) or not validCF(v) then return end
  d.props.Position = V3.new(v.X, v.Y, v.Z)
  local rx, ry, rz = v:ToOrientation()
  d.props.Orientation = V3.new(deg(rx), deg(ry), deg(rz))
  wake(d)
end

HK.Orientation = function(d, v)
  if not isPartData(d) or rawtype(v) ~= "table" or v.X == nil then return end
  local cf = d.props.CFrame
  if not validCF(cf) then return end
  local ncf = CF.new(cf.X, cf.Y, cf.Z) * CF.fromOrientation(rad(v.X), rad(v.Y), rad(v.Z))
  d.props.CFrame = ncf
  wake(d)
end

local function setVelocity(d, v)
  if not isPartData(d) or rawtype(v) ~= "table" or v.X == nil then return end
  local ph = d.phys
  if not ph then ph = { vx = 0, vy = 0, vz = 0, rest = false, wake = 0 }; d.phys = ph end
  ph.vx, ph.vy, ph.vz = v.X, v.Y, v.Z
  ph.rest = false
  d.props.AssemblyLinearVelocity = v
  d.props.Velocity = v
end
HK.AssemblyLinearVelocity = setVelocity
HK.Velocity = setVelocity
HK.Anchored = function(d) if isPartData(d) then wake(d) end end

local function setState(d, name)
  local old = d.state or "Running"
  if old == name then return end
  d.state = name
  if d.signals.StateChanged then
    X.fire(d.signals.StateChanged, Enum.HumanoidStateType[old], Enum.HumanoidStateType[name])
  end
end

local function die(d)
  setState(d, "Dead")
  d.deadAt = now()
  if d.signals.Died then X.fire(d.signals.Died) end
end

local function applyHealth(d, v)
  if rawtype(v) ~= "number" or v ~= v then v = 0 end
  local mx = d.props.MaxHealth
  if rawtype(mx) ~= "number" then mx = 100 end
  if v > mx then v = mx end
  if v < 0 then v = 0 end
  return v
end

HK.Health = function(d, v, old)
  if d.class ~= "Humanoid" then return end
  local c = applyHealth(d, v)
  d.props.Health = c
  if c ~= old and d.signals.HealthChanged then X.fire(d.signals.HealthChanged, c) end
  if c <= 0 and not d.dead then
    d.dead = true
    die(d)
  elseif c > 0 then
    d.dead = false
  end
end

HK.MaxHealth = function(d, v)
  if d.class ~= "Humanoid" then return end
  if rawtype(d.props.Health) == "number" and d.props.Health > v then
    HK.Health(d, v, d.props.Health)
  end
end

-- extra Humanoid events that the client has
do
  local ev = X.EVENTS.Humanoid
  local have = {}
  for _, e in ipairs(ev) do have[e] = true end
  local more = { "MoveToFinished", "FreeFalling", "FallingDown", "GettingUp", "Climbing", "Swimming",
    "PlatformStanding", "Strafing", "StateEnabledChanged", "Touched" }
  for _, e in ipairs(more) do
    if not have[e] then ev[#ev + 1] = e end
    if not humD.signals[e] then humD.signals[e] = X.newSignal(e) end
  end
end

------------------------------------------------------------------------
-- R15 style character
------------------------------------------------------------------------
local SKIN = C3.new(0.99, 0.82, 0.55)
local SHIRT = C3.new(0.05, 0.41, 0.67)
local PANTS = C3.new(0.16, 0.55, 0.35)

-- name, offX, offY, offZ, sizeX, sizeY, sizeZ, color, jointName, parentPartName
local R15 = {
  { "LowerTorso", 0, -0.8, 0, 2, 0.4, 1, SHIRT, "Root", "HumanoidRootPart" },
  { "UpperTorso", 0, 0.2, 0, 2, 1.6, 1, SHIRT, "Waist", "LowerTorso" },
  { "Head", 0, 1.7, 0, 1.2, 1.2, 1.2, SKIN, "Neck", "UpperTorso" },
  { "LeftUpperArm", -1.5, 0.5, 0, 1, 1.2, 1, SHIRT, "LeftShoulder", "UpperTorso" },
  { "LeftLowerArm", -1.5, -0.6, 0, 1, 1.1, 1, SKIN, "LeftElbow", "LeftUpperArm" },
  { "LeftHand", -1.5, -1.3, 0, 1, 0.3, 1, SKIN, "LeftWrist", "LeftLowerArm" },
  { "RightUpperArm", 1.5, 0.5, 0, 1, 1.2, 1, SHIRT, "RightShoulder", "UpperTorso" },
  { "RightLowerArm", 1.5, -0.6, 0, 1, 1.1, 1, SKIN, "RightElbow", "RightUpperArm" },
  { "RightHand", 1.5, -1.3, 0, 1, 0.3, 1, SKIN, "RightWrist", "RightLowerArm" },
  { "LeftUpperLeg", -0.5, -1.4, 0, 1, 1.2, 1, PANTS, "LeftHip", "LowerTorso" },
  { "LeftLowerLeg", -0.5, -2.3, 0, 1, 1.0, 1, PANTS, "LeftKnee", "LeftUpperLeg" },
  { "LeftFoot", -0.5, -2.85, 0, 1, 0.3, 1, PANTS, "LeftAnkle", "LeftLowerLeg" },
  { "RightUpperLeg", 0.5, -1.4, 0, 1, 1.2, 1, PANTS, "RightHip", "LowerTorso" },
  { "RightLowerLeg", 0.5, -2.3, 0, 1, 1.0, 1, PANTS, "RightKnee", "RightUpperLeg" },
  { "RightFoot", 0.5, -2.85, 0, 1, 0.3, 1, PANTS, "RightAnkle", "RightLowerLeg" },
}

local charParts = {}   -- list of data tables that follow the root part

do
  hrpD.charPart = true
  hrpD.props.Size = V3.new(2, 2, 1)
  hrpD.props.Transparency = 1
  hrpD.props.CanCollide = false
  hrpD.props.Color = C3.new(0.63, 0.64, 0.63)
  local byName = { HumanoidRootPart = hrpP }
  for _, row in ipairs(R15) do
    local name = row[1]
    local p
    if name == "Head" then
      p = X.head
    else
      p = mk("Part", name, charModel)
    end
    local d = D[p]
    d.charPart = true
    d.charOffset = V3.new(row[2], row[3], row[4])
    d.props.Size = V3.new(row[5], row[6], row[7])
    d.props.Color = row[8]
    d.props.CanCollide = false
    d.props.Anchored = false
    byName[name] = p
    charParts[#charParts + 1] = d
  end
  for _, row in ipairs(R15) do
    local part, parent = byName[row[1]], byName[row[10]]
    local j = mk("Motor6D", row[9], part)
    D[j].props.Part0 = parent
    D[j].props.Part1 = part
  end
  mk("Animator", "Animator", humP)
  humD.props.RigType = Enum.HumanoidRigType.R15
  humD.props.DisplayName = "Player1"
  humD.props.RootPart = hrpP
  humD.props.HipHeight = 2
  humD.state = "Running"
  humD.dead = false
  humD.vy = 0
end

-- properties the real LocalPlayer has
do
  local p = lpD.props
  if p.UserId == nil then p.UserId = 1 end
  if p.DisplayName == nil then p.DisplayName = "Player1" end
  if p.AccountAge == nil then p.AccountAge = 1000 end
  if p.MembershipType == nil then p.MembershipType = Enum.MembershipType.None end
  if p.Neutral == nil then p.Neutral = true end
  if p.CameraMode == nil then p.CameraMode = Enum.CameraMode.Classic end
  if p.RespawnLocation == nil then p.RespawnLocation = nil end
  if p.CharacterAppearanceId == nil then p.CharacterAppearanceId = 1 end
end

-- the default places that were placed with Position only
for _, p in ipairs(allParts()) do
  local pos = p.props.Position
  if pos then
    local cf = p.props.CFrame
    if not validCF(cf) or cf.X ~= pos.X or cf.Y ~= pos.Y or cf.Z ~= pos.Z then
      p.props.CFrame = CF.new(pos.X, pos.Y, pos.Z)
    end
    local cfn = p.props.CFrame
    local rx, ry, rz = cfn:ToOrientation()
    p.props.Orientation = V3.new(deg(rx), deg(ry), deg(rz))
  end
end
D[X.spawnLoc].props.Position = V3.new(0, 0.5, 0)
D[X.spawnLoc].props.CFrame = CF.new(0, 0.5, 0)
D[X.spawnLoc].props.Size = V3.new(6, 1, 6)
D[X.spawnLoc].props.Anchored = true
D[X.spawnLoc].props.Color = C3.new(0.64, 0.64, 0.64)
D[X.baseplate].props.Color = C3.new(0.39, 0.37, 0.38)
D[X.baseplate].props.Material = Enum.Material.Grass
D[X.baseplate].props.Anchored = true
HK.CFrame(D[X.spawnLoc], D[X.spawnLoc].props.CFrame)

------------------------------------------------------------------------
-- input / camera access
------------------------------------------------------------------------
local function inputState()
  if H.moveinput then
    local jx, jy, jump = H.moveinput()
    return jx or 0, jy or 0, jump and true or false
  end
  return 0, 0, false
end

local function cameraState()
  if H.camera then
    local yaw, pitch, dist = H.camera()
    return yaw or 0, pitch or 0.3, dist or 14
  end
  return 0, 0.3, 14
end

local function viewSize()
  if H.vsize then
    local w, h = H.vsize()
    if w and w > 0 and h and h > 0 then return w, h end
  end
  return 800, 450
end

local function updateCamera()
  local ct = camD.props.CameraType
  if ct and ct.Name == "Scriptable" then return end
  local yaw, pitch, dist = cameraState()
  local h = hrpD.props.CFrame
  local tx, ty, tz = h.X, h.Y + 1.5, h.Z
  local cp = cos(pitch)
  local pos = V3.new(tx + dist * sin(yaw) * cp, ty + dist * sin(pitch), tz + dist * cos(yaw) * cp)
  camD.props.CFrame = CFmath.lookAt(pos, V3.new(tx, ty, tz))
  camD.props.Focus = CF.new(tx, ty, tz)
  camD.props.ViewportSize = V2.new(viewSize())
end

------------------------------------------------------------------------
-- stepping: loose parts
------------------------------------------------------------------------
local function overlapAt(x, y, z, ex, ey, ez, solids, skip)
  for j = 1, #solids do
    local s = solids[j]
    if s.d ~= skip then
      local b = s.bb
      if x - ex < b.x1 and x + ex > b.x0 and y - ey < b.y1 and y + ey > b.y0 and z - ez < b.z1 and z + ez > b.z0 then
        return b
      end
    end
  end
  return nil
end

local function stepParts(dt, parts, solids, t)
  local g = wsD.props.Gravity
  if rawtype(g) ~= "number" then g = 196.2 end
  local killY = wsD.props.FallenPartsDestroyHeight
  if rawtype(killY) ~= "number" then killY = -500 end
  for i = 1, #parts do
    local d = parts[i]
    if not d.props.Anchored and not d.charPart and not d.destroyed and validCF(d.props.CFrame) then
      local ph = d.phys
      if not ph then ph = { vx = 0, vy = 0, vz = 0, rest = false, wake = 0 }; d.phys = ph end
      if ph.rest and t < ph.wake then
        -- sleeping
      else
        ph.rest = false
        ph.vy = ph.vy - g * dt
        local bb = bbOf(d)
        if bb then
          local cf = d.props.CFrame
          local ex, ey, ez = bb.ex, bb.ey, bb.ez
          local x, y, z = cf.X, cf.Y, cf.Z
          local grounded = false
          local collide = d.props.CanCollide ~= false
          local ny = y + ph.vy * dt
          if collide then
            local hit = overlapAt(x, ny, z, ex, ey, ez, solids, d)
            if hit then
              if ph.vy < 0 then ny = hit.y1 + ey; grounded = true else ny = hit.y0 - ey end
              ph.vy = 0
            end
          end
          local nx = x + ph.vx * dt
          if collide and overlapAt(nx, ny, z, ex, ey, ez, solids, d) then nx = x; ph.vx = 0 end
          local nz = z + ph.vz * dt
          if collide and overlapAt(nx, ny, nz, ex, ey, ez, solids, d) then nz = z; ph.vz = 0 end
          if grounded then
            local f = 1 - min(1, 6 * dt)
            ph.vx, ph.vz = ph.vx * f, ph.vz * f
            if abs(ph.vx) + abs(ph.vz) < 0.1 then
              ph.vx, ph.vz = 0, 0
              ph.rest = true
              ph.wake = t + 0.5
            end
          end
          if nx ~= x or ny ~= y or nz ~= z then
            setCF(d, cf + V3.new(nx - x, ny - y, nz - z))
          end
          local vel = V3.new(ph.vx, ph.vy, ph.vz)
          d.props.AssemblyLinearVelocity = vel
          d.props.Velocity = vel
          if ny < killY then
            local okd = pcall(Methods.Destroy, d.proxy)
          end
        end
      end
    end
  end
end

------------------------------------------------------------------------
-- stepping: the character / Humanoid
------------------------------------------------------------------------
local function wrapAngle(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

local STEP_H = 1.6
local lastRespawnLog = 0

local function respawn()
  humD.dead = false
  humD.props.Health = humD.props.MaxHealth or 100
  humD.vy = 0
  humD.moveTarget = nil
  humD.moveVec = nil
  local sp = D[X.spawnLoc].props.CFrame
  setCF(hrpD, CF.new(sp.X, sp.Y + 4, sp.Z))
  setState(humD, "Running")
  X.fire(lpD.signals.CharacterRemoving, charModel)
  X.fire(lpD.signals.CharacterAdded, charModel)
  if humD.signals.HealthChanged then X.fire(humD.signals.HealthChanged, humD.props.Health) end
end

local function followLimbs()
  local rcf = hrpD.props.CFrame
  for i = 1, #charParts do
    local d = charParts[i]
    local o = d.charOffset
    setCF(d, rcf * CF.new(o.X, o.Y, o.Z))
  end
end

local function stepCharacter(dt, solids, t)
  if humD.dead then
    if humD.deadAt and t - humD.deadAt > 5 then respawn() end
    return
  end
  local cf = hrpD.props.CFrame
  if not validCF(cf) then return end
  local x, y, z = cf.X, cf.Y, cf.Z
  local jx, jy, jumpIn = inputState()
  local hp = humD.props
  local speed = hp.WalkSpeed
  if rawtype(speed) ~= "number" then speed = 16 end
  local hip = hp.HipHeight
  if rawtype(hip) ~= "number" then hip = 2 end
  local stand = hip + 1
  local g = wsD.props.Gravity
  if rawtype(g) ~= "number" then g = 196.2 end

  -- desired horizontal direction
  local dx, dz = 0, 0
  if jx ~= 0 or jy ~= 0 then
    local look = camD.props.CFrame.LookVector
    local fx, fz = look.X, look.Z
    local fm = sqrt(fx * fx + fz * fz)
    if fm < 1e-4 then fx, fz = 0, -1 else fx, fz = fx / fm, fz / fm end
    local rx, rz = -fz, fx
    dx, dz = rx * jx + fx * jy, rz * jx + fz * jy
  elseif humD.moveVec then
    dx, dz = humD.moveVec[1], humD.moveVec[2]
  elseif humD.moveTarget then
    local mt = humD.moveTarget
    local ddx, ddz = mt[1] - x, mt[3] - z
    local dist = sqrt(ddx * ddx + ddz * ddz)
    if dist < 1.2 then
      humD.moveTarget = nil
      X.fire(humD.signals.MoveToFinished, true)
    elseif t - humD.moveStart > 8 then
      humD.moveTarget = nil
      X.fire(humD.signals.MoveToFinished, false)
    else
      dx, dz = ddx / dist, ddz / dist
    end
  end
  local dm = sqrt(dx * dx + dz * dz)
  if dm > 1 then dx, dz = dx / dm, dz / dm; dm = 1 end
  hp.MoveDirection = V3.new(dx, 0, dz)

  local feet = y - stand
  local top = y + 2.3
  -- horizontal movement with obstacle checks (obstacles higher than a step block)
  local function blocked(px, pz)
    for j = 1, #solids do
      local s = solids[j]
      local b = s.bb
      if px - 1 < b.x1 and px + 1 > b.x0 and pz - 1 < b.z1 and pz + 1 > b.z0 and b.y1 > feet + STEP_H and b.y0 < top then
        return true
      end
    end
    return false
  end
  local nx, nz = x, z
  if dm > 0 then
    local tx = x + dx * speed * dt
    if not blocked(tx, z) then nx = tx end
    local tz = z + dz * speed * dt
    if not blocked(nx, tz) then nz = tz end
  end

  -- ground below the feet
  local groundY = -1e9
  for j = 1, #solids do
    local b = solids[j].bb
    if nx - 0.9 < b.x1 and nx + 0.9 > b.x0 and nz - 0.9 < b.z1 and nz + 0.9 > b.z0 and b.y1 <= feet + STEP_H and b.y1 > groundY then
      groundY = b.y1
    end
  end

  local vy = humD.vy or 0
  local grounded = (feet <= groundY + 0.05) and vy <= 0
  local ny = y
  if grounded then
    ny = groundY + stand
    vy = 0
  else
    vy = vy - g * dt
    ny = y + vy * dt
    if ny - stand < groundY then
      ny = groundY + stand
      if vy < 0 then
        if humD.state == "Freefall" or humD.state == "Jumping" then setState(humD, "Landed") end
      end
      vy = 0
      grounded = true
    end
    -- ceiling
    if vy > 0 then
      for j = 1, #solids do
        local b = solids[j].bb
        if nx - 0.9 < b.x1 and nx + 0.9 > b.x0 and nz - 0.9 < b.z1 and nz + 0.9 > b.z0 and b.y0 >= top - 0.05 and ny + 2.3 > b.y0 then
          ny = b.y0 - 2.3
          vy = 0
        end
      end
    end
  end
  local wantJump = jumpIn or hp.Jump == true
  if wantJump and grounded and not hp.PlatformStand then
    local jp = hp.JumpPower
    if rawtype(jp) ~= "number" then jp = 50 end
    if hp.UseJumpPower == false and rawtype(hp.JumpHeight) == "number" then jp = sqrt(2 * g * hp.JumpHeight) end
    vy = jp
    grounded = false
    ny = ny + 0.05
    setState(humD, "Jumping")
    X.fire(humD.signals.Jumping, true)
    hp.Jump = false
  elseif hp.Jump == true then
    hp.Jump = false
  end
  humD.vy = vy

  if not grounded and humD.state ~= "Jumping" and vy < 0 then setState(humD, "Freefall") end
  if vy < 0 and humD.state == "Jumping" then setState(humD, "Freefall") end
  if grounded and (humD.state == "Freefall" or humD.state == "Landed" or humD.state == "Jumping") and vy == 0 then
    setState(humD, "Running")
  end

  -- facing
  local ry = select(2, cf:ToOrientation())
  if dm > 0.01 and hp.AutoRotate ~= false then
    local target = atan2(-dx, -dz)
    local delta = wrapAngle(target - ry)
    local maxTurn = 14 * dt
    if delta > maxTurn then delta = maxTurn elseif delta < -maxTurn then delta = -maxTurn end
    ry = ry + delta
  end
  local moved = (nx ~= x) or (nz ~= z)
  if moved and humD.signals.Running then X.fire(humD.signals.Running, speed * dm) end
  if not moved and humD.lastMoved and humD.signals.Running then X.fire(humD.signals.Running, 0) end
  humD.lastMoved = moved

  setCF(hrpD, CF.new(nx, ny, nz) * CF.Angles(0, ry, 0))
  followLimbs()
  if ny < (wsD.props.FallenPartsDestroyHeight or -500) then
    HK.Health(humD, 0, humD.props.Health)
  end
end

------------------------------------------------------------------------
-- Touched / TouchEnded
------------------------------------------------------------------------
local touching = {}

local function touchTick(parts)
  local hb = bbOf(hrpD)
  local cfc = hrpD.props.CFrame
  local charBox
  if cfc then
    charBox = { x0 = cfc.X - 1, x1 = cfc.X + 1, y0 = cfc.Y - 3, y1 = cfc.Y + 2.3, z0 = cfc.Z - 1, z1 = cfc.Z + 1 }
  end
  for i = 1, #parts do
    local w = parts[i]
    local sT, sE = w.signals.Touched, w.signals.TouchEnded
    if sT and (#sT.__conns > 0 or #sE.__conns > 0) and w.props.CanTouch ~= false and not w.charPart then
      local wb = bbOf(w)
      if wb then
        if charBox then
          local key = w.id .. ":c"
          local hit = overlap(wb, charBox, 0.05) and not humD.dead
          if hit and not touching[key] then
            touching[key] = true
            X.fire(sT, hrpP)
          elseif not hit and touching[key] then
            touching[key] = nil
            X.fire(sE, hrpP)
          end
        end
        for j = 1, #parts do
          local p = parts[j]
          if p ~= w and not p.charPart and p.props.CanTouch ~= false and (not w.props.Anchored or not p.props.Anchored) then
            local pb = bbOf(p)
            if pb then
              local key = w.id .. ":" .. p.id
              local hit = overlap(wb, pb, 0.05)
              if hit and not touching[key] then
                touching[key] = true
                X.fire(sT, p.proxy)
              elseif not hit and touching[key] then
                touching[key] = nil
                X.fire(sE, p.proxy)
              end
            end
          end
        end
      end
    end
  end
end

------------------------------------------------------------------------
-- world step (called every frame from the scheduler)
------------------------------------------------------------------------
X.worldStep = function(dt)
  local t = now()
  local parts = allParts()
  local solids = {}
  for i = 1, #parts do
    local d = parts[i]
    if not d.charPart and d.props.CanCollide ~= false then
      local bb = bbOf(d)
      if bb then solids[#solids + 1] = { d = d, bb = bb } end
    end
  end
  stepParts(dt, parts, solids, t)
  -- bounding boxes of parts that just moved are rebuilt lazily by bbOf
  for i = 1, #solids do solids[i].bb = bbOf(solids[i].d) or solids[i].bb end
  stepCharacter(dt, solids, t)
  touchTick(parts)
  updateCamera()
end

------------------------------------------------------------------------
-- Humanoid methods
------------------------------------------------------------------------
local CMH = CM.Humanoid
CMH.TakeDamage = function(self, n)
  local d = D[self]
  if rawtype(n) ~= "number" then error("invalid argument #1 to 'TakeDamage' (number expected)", 2) end
  for _, c in ipairs(D[d.parent or self].children) do
    if D[c].class == "ForceField" then return end
  end
  HK.Health(d, d.props.Health - n, d.props.Health)
  -- apply (the hook only normalises, so set the value that the hook computed)
end
CMH.GetState = function(self) return Enum.HumanoidStateType[D[self].state or "Running"] end
CMH.ChangeState = function(self, st)
  local d = D[self]
  local name = type(st) == "table" and st.Name or tostring(st)
  setState(d, name)
  if name == "Jumping" then d.props.Jump = true end
end
CMH.SetStateEnabled = function() end
CMH.GetStateEnabled = function() return true end
CMH.MoveTo = function(self, pos, part)
  local d = D[self]
  if part then
    local cf = D[part].props.CFrame
    if validCF(cf) then pos = cf * pos end
  end
  d.moveTarget = { pos.X, pos.Y, pos.Z }
  d.moveVec = nil
  d.moveStart = now()
end
CMH.Move = function(self, dir)
  local d = D[self]
  if dir and (dir.X ~= 0 or dir.Z ~= 0) then
    local m = sqrt(dir.X * dir.X + dir.Z * dir.Z)
    d.moveVec = { dir.X / max(m, 1), dir.Z / max(m, 1) }
  else
    d.moveVec = nil
  end
  d.moveTarget = nil
end
CMH.CancelMoveTo = function(self) D[self].moveTarget = nil end

local function makeTrack(anim)
  local track = { IsPlaying = false, Length = 1, Looped = false, Speed = 1, TimePosition = 0, Priority = Enum.AnimationPriority.Core,
    WeightCurrent = 1, WeightTarget = 1, Animation = anim }
  track.Stopped = X.newSignal("Stopped")
  track.Ended = X.newSignal("Ended")
  track.DidLoop = X.newSignal("DidLoop")
  track.KeyframeReached = X.newSignal("KeyframeReached")
  local methods = {}
  function methods.Play(self) self.IsPlaying = true end
  function methods.Stop(self)
    self.IsPlaying = false
    X.fire(self.Stopped)
    X.fire(self.Ended)
  end
  function methods.AdjustSpeed(self, s) self.Speed = s end
  function methods.AdjustWeight(self, w) self.WeightTarget = w end
  function methods.GetMarkerReachedSignal() return X.newSignal("MarkerReached") end
  function methods.GetTimeOfKeyframe() return 0 end
  return setmetatable(track, { __rbxtype = "AnimationTrack", __index = methods, __tostring = function() return "AnimationTrack" end })
end
CMH.LoadAnimation = function(_, anim) return makeTrack(anim) end
CM.Animator = { LoadAnimation = function(_, anim) return makeTrack(anim) end,
  GetPlayingAnimationTracks = function() return {} end }
CMH.GetPlayingAnimationTracks = function() return {} end
CMH.GetAppliedDescription = function() return nil end
CMH.RemoveAccessories = function() end
CMH.AddAccessory = function() end
CMH.BuildRigFromAttachments = function() end
CMH.ApplyDescription = function() end

------------------------------------------------------------------------
-- BasePart / Model methods
------------------------------------------------------------------------
local function partVolume(d)
  local s = d.props.Size
  return (s and s.X * s.Y * s.Z) or 0
end

CM.BasePart.GetMass = function(self) return max(0.001, partVolume(D[self]) * 0.7) end
CM.BasePart.GetPivot = function(self) return D[self].props.CFrame end
CM.BasePart.PivotTo = function(self, cf)
  if not validCF(cf) then error("invalid argument #1 to 'PivotTo' (CFrame expected)", 2) end
  setCF(D[self], cf)
end
CM.BasePart.ApplyImpulse = function(self, v)
  local d = D[self]
  local ph = d.phys
  if not ph then ph = { vx = 0, vy = 0, vz = 0, rest = false, wake = 0 }; d.phys = ph end
  local m = max(0.001, partVolume(d) * 0.7)
  ph.vx, ph.vy, ph.vz = ph.vx + v.X / m, ph.vy + v.Y / m, ph.vz + v.Z / m
  ph.rest = false
end
CM.BasePart.GetVelocityAtPosition = function(self)
  local ph = D[self].phys
  if not ph then return V3.new(0, 0, 0) end
  return V3.new(ph.vx, ph.vy, ph.vz)
end
CM.BasePart.IsGrounded = function(self) return D[self].props.Anchored == true end
CM.BasePart.GetTouchingParts = function(self)
  local d = D[self]
  local b = bbOf(d)
  local out = {}
  if not b then return out end
  for _, p in ipairs(allParts()) do
    if p ~= d and p.props.CanTouch ~= false then
      local pb = bbOf(p)
      if pb and overlap(b, pb, 0.05) then out[#out + 1] = p.proxy end
    end
  end
  return out
end
CM.BasePart.GetConnectedParts = function() return {} end
CM.BasePart.CanCollideWith = function(_, other) return D[other].props.CanCollide ~= false end

local function modelParts(self)
  local out = {}
  gather(D[self], out)
  return out
end

local function modelBox(self)
  local ps = modelParts(self)
  local x0, x1, y0, y1, z0, z1 = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
  local n = 0
  for _, d in ipairs(ps) do
    local b = bbOf(d)
    if b then
      n = n + 1
      x0, x1 = min(x0, b.x0), max(x1, b.x1)
      y0, y1 = min(y0, b.y0), max(y1, b.y1)
      z0, z1 = min(z0, b.z0), max(z1, b.z1)
    end
  end
  if n == 0 then return CF.new(0, 0, 0), V3.new(0, 0, 0), 0 end
  return CF.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), V3.new(x1 - x0, y1 - y0, z1 - z0), n
end

local function modelPivot(self)
  local d = D[self]
  local pp = d.props.PrimaryPart
  if pp and D[pp] and validCF(D[pp].props.CFrame) then return D[pp].props.CFrame end
  local c = modelBox(self)
  return c
end

local function pivotModel(self, cf)
  local pivot = modelPivot(self)
  local delta = cf * pivot:Inverse()
  for _, d in ipairs(modelParts(self)) do
    if validCF(d.props.CFrame) then setCF(d, delta * d.props.CFrame) end
  end
  if D[self].props.PrimaryPart == nil then D[self].props.CFrame = cf end
end

CM.Model.GetPivot = modelPivot
CM.Model.PivotTo = function(self, cf)
  if not validCF(cf) then error("invalid argument #1 to 'PivotTo' (CFrame expected)", 2) end
  pivotModel(self, cf)
end
CM.Model.MoveTo = function(self, pos)
  local pivot = modelPivot(self)
  pivotModel(self, CF.new(pos.X, pos.Y, pos.Z) * pivot.Rotation)
end
CM.Model.TranslateBy = function(self, v)
  local pivot = modelPivot(self)
  pivotModel(self, pivot + v)
end
CM.Model.SetPrimaryPartCFrame = CM.Model.PivotTo
CM.Model.GetBoundingBox = function(self)
  local c, s = modelBox(self)
  return c, s
end
CM.Model.GetExtentsSize = function(self)
  local _, s = modelBox(self)
  return s
end
CM.Model.ScaleTo = function() end
CM.Model.GetScale = function() return 1 end

------------------------------------------------------------------------
-- Ray, RaycastParams, OverlapParams, Raycast, spatial queries
------------------------------------------------------------------------
local RayMT = { __rbxtype = "Ray", __tostring = function(r) return "Ray" end }
RayMT.__index = function(r, k)
  if k == "Unit" then
    local d = rawget(r, "Direction")
    local m = sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
    return setmetatable({ Origin = rawget(r, "Origin"), Direction = m > 0 and d / m or d }, RayMT)
  elseif k == "ClosestPoint" then
    return function(self, p)
      local o, d = self.Origin, self.Direction
      local dd = d.X * d.X + d.Y * d.Y + d.Z * d.Z
      local t = dd > 0 and max(0, min(1, ((p.X - o.X) * d.X + (p.Y - o.Y) * d.Y + (p.Z - o.Z) * d.Z) / dd)) or 0
      return V3.new(o.X + d.X * t, o.Y + d.Y * t, o.Z + d.Z * t)
    end
  elseif k == "Distance" then
    return function(self, p)
      local c = self:ClosestPoint(p)
      return sqrt((c.X - p.X) ^ 2 + (c.Y - p.Y) ^ 2 + (c.Z - p.Z) ^ 2)
    end
  end
  return nil
end
local Ray = { new = function(o, d) return setmetatable({ Origin = o, Direction = d }, RayMT) end }

local function newParams(name, extra)
  local methods = {}
  local mt = { __rbxtype = name, __index = methods, __tostring = function() return name end }
  function methods.AddToFilter(self, item)
    local list = rawget(self, "FilterDescendantsInstances") or {}
    if rawtype(item) == "table" and not X.isInstance(item) then
      for _, v in ipairs(item) do list[#list + 1] = v end
    else
      list[#list + 1] = item
    end
    rawset(self, "FilterDescendantsInstances", list)
  end
  local t = { FilterDescendantsInstances = {}, FilterType = Enum.RaycastFilterType.Exclude,
    CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false, IgnoreWater = false }
  if extra then for k, v in pairs(extra) do t[k] = v end end
  return setmetatable(t, mt)
end
local RaycastParams = { new = function() return newParams("RaycastParams") end }
local OverlapParams = { new = function()
  return newParams("OverlapParams", { MaxParts = 0, FilterType = Enum.RaycastFilterType.Exclude })
end }

local function inFilterList(d, list)
  local cur = d.proxy
  while cur do
    for _, item in ipairs(list) do
      if item == cur then return true end
    end
    local cd = D[cur]
    cur = cd and cd.parent or nil
  end
  return false
end

local function passes(d, params)
  if d.props.CanQuery == false then return false end
  if not params then return true end
  local list = rawget(params, "FilterDescendantsInstances") or {}
  local ft = rawget(params, "FilterType")
  local include = ft and (ft.Name == "Include" or ft.Name == "Whitelist")
  local listed = inFilterList(d, list)
  if include then return listed end
  return not listed
end

local function rayBox(ox, oy, oz, dx, dy, dz, b)
  local o = { ox, oy, oz }
  local dd = { dx, dy, dz }
  local lo = { b.x0, b.y0, b.z0 }
  local hi = { b.x1, b.y1, b.z1 }
  local tmin, tmax = 0, 1
  local axis, sgn = nil, 0
  for i = 1, 3 do
    local di = dd[i]
    if abs(di) < 1e-12 then
      if o[i] < lo[i] or o[i] > hi[i] then return nil end
    else
      local t1 = (lo[i] - o[i]) / di
      local t2 = (hi[i] - o[i]) / di
      local s = -1
      if t1 > t2 then t1, t2 = t2, t1; s = 1 end
      if t1 > tmin then tmin = t1; axis = i; sgn = s end
      if t2 < tmax then tmax = t2 end
      if tmin > tmax then return nil end
    end
  end
  if not axis then return nil end
  return tmin, axis, sgn
end

local RayResultMT = { __rbxtype = "RaycastResult", __tostring = function() return "RaycastResult" end }

local function raycast(origin, direction, params)
  if rawtype(origin) ~= "table" or origin.X == nil then error("invalid argument #1 to 'Raycast' (Vector3 expected)", 3) end
  if rawtype(direction) ~= "table" or direction.X == nil then error("invalid argument #2 to 'Raycast' (Vector3 expected)", 3) end
  local best, bestD, bestAxis, bestSgn
  for _, d in ipairs(allParts()) do
    if passes(d, params) then
      local b = bbOf(d)
      if b then
        local tt, axis, sgn = rayBox(origin.X, origin.Y, origin.Z, direction.X, direction.Y, direction.Z, b)
        if tt and (not best or tt < best) then best, bestD, bestAxis, bestSgn = tt, d, axis, sgn end
      end
    end
  end
  if not best then return nil end
  local len = sqrt(direction.X ^ 2 + direction.Y ^ 2 + direction.Z ^ 2)
  local n = { 0, 0, 0 }
  n[bestAxis] = bestSgn
  return setmetatable({
    Instance = bestD.proxy,
    Position = V3.new(origin.X + direction.X * best, origin.Y + direction.Y * best, origin.Z + direction.Z * best),
    Normal = V3.new(n[1], n[2], n[3]),
    Distance = best * len,
    Material = bestD.props.Material or Enum.Material.Plastic,
  }, RayResultMT)
end

CM.Workspace.Raycast = function(_, o, d, params) return raycast(o, d, params) end
CM.Workspace.FindPartOnRay = function(_, ray)
  local r = raycast(ray.Origin, ray.Direction, nil)
  if r then return r.Instance, r.Position, r.Normal, r.Material end
  return nil, V3.new(ray.Origin.X + ray.Direction.X, ray.Origin.Y + ray.Direction.Y, ray.Origin.Z + ray.Direction.Z)
end
CM.Workspace.FindPartOnRayWithIgnoreList = function(_, ray, ignore)
  local p = newParams("RaycastParams")
  rawset(p, "FilterDescendantsInstances", ignore or {})
  local r = raycast(ray.Origin, ray.Direction, p)
  if r then return r.Instance, r.Position, r.Normal, r.Material end
  return nil, V3.new(ray.Origin.X + ray.Direction.X, ray.Origin.Y + ray.Direction.Y, ray.Origin.Z + ray.Direction.Z)
end
CM.Workspace.FindPartOnRayWithWhitelist = function(_, ray, list)
  local p = newParams("RaycastParams")
  rawset(p, "FilterDescendantsInstances", list or {})
  rawset(p, "FilterType", Enum.RaycastFilterType.Include)
  local r = raycast(ray.Origin, ray.Direction, p)
  if r then return r.Instance, r.Position, r.Normal, r.Material end
  return nil, V3.new(ray.Origin.X + ray.Direction.X, ray.Origin.Y + ray.Direction.Y, ray.Origin.Z + ray.Direction.Z)
end

local function boxFromCF(cf, size)
  local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
  local ex = abs(cf.R00) * hx + abs(cf.R01) * hy + abs(cf.R02) * hz
  local ey = abs(cf.R10) * hx + abs(cf.R11) * hy + abs(cf.R12) * hz
  local ez = abs(cf.R20) * hx + abs(cf.R21) * hy + abs(cf.R22) * hz
  return { x0 = cf.X - ex, x1 = cf.X + ex, y0 = cf.Y - ey, y1 = cf.Y + ey, z0 = cf.Z - ez, z1 = cf.Z + ez }
end

local function queryBox(box, params, skip)
  local out = {}
  local limit = params and rawget(params, "MaxParts") or 0
  for _, d in ipairs(allParts()) do
    if d ~= skip and passes(d, params) then
      local b = bbOf(d)
      if b and overlap(box, b) then
        out[#out + 1] = d.proxy
        if limit and limit > 0 and #out >= limit then break end
      end
    end
  end
  return out
end

CM.Workspace.GetPartBoundsInBox = function(_, cf, size, params) return queryBox(boxFromCF(cf, size), params) end
CM.Workspace.GetPartBoundsInRadius = function(_, pos, radius, params)
  local out = {}
  for _, d in ipairs(allParts()) do
    if passes(d, params) then
      local b = bbOf(d)
      if b then
        local cx = max(b.x0, min(pos.X, b.x1)) - pos.X
        local cy = max(b.y0, min(pos.Y, b.y1)) - pos.Y
        local cz = max(b.z0, min(pos.Z, b.z1)) - pos.Z
        if cx * cx + cy * cy + cz * cz <= radius * radius then out[#out + 1] = d.proxy end
      end
    end
  end
  return out
end
CM.Workspace.GetPartsInPart = function(_, part, params)
  local d = D[part]
  local b = bbOf(d)
  if not b then return {} end
  return queryBox(b, params, d)
end
CM.Workspace.GetNumAwakeParts = function() return 0 end
CM.Workspace.GetRealPhysicsFPS = function() return 60 end
CM.Workspace.PGSIsEnabled = function() return true end

------------------------------------------------------------------------
-- Camera
------------------------------------------------------------------------
local function projectPoint(v)
  local cf = camD.props.CFrame
  local w, h = viewSize()
  local rel = cf:PointToObjectSpace(v)
  local depth = -rel.Z
  local fov = camD.props.FieldOfView
  if rawtype(fov) ~= "number" then fov = 70 end
  local fy = (h / 2) / math.tan(rad(fov) / 2)
  if depth <= 1e-6 then
    return V3.new(w / 2 + fy * rel.X * 1e6, h / 2 - fy * rel.Y * 1e6, depth), false
  end
  local sx = w / 2 + fy * rel.X / depth
  local sy = h / 2 - fy * rel.Y / depth
  return V3.new(sx, sy, depth), depth > 0 and sx >= 0 and sx <= w and sy >= 0 and sy <= h
end

CM.Camera = CM.Camera or {}
CM.Camera.WorldToViewportPoint = function(_, v) return projectPoint(v) end
CM.Camera.WorldToScreenPoint = CM.Camera.WorldToViewportPoint
local function pixelRay(x, y, depth)
  local cf = camD.props.CFrame
  local w, h = viewSize()
  local fov = camD.props.FieldOfView
  if rawtype(fov) ~= "number" then fov = 70 end
  local fy = (h / 2) / math.tan(rad(fov) / 2)
  local dirLocal = V3.new((x - w / 2) / fy, -(y - h / 2) / fy, -1)
  local dir = cf:VectorToWorldSpace(dirLocal)
  local m = sqrt(dir.X ^ 2 + dir.Y ^ 2 + dir.Z ^ 2)
  dir = dir / m
  local o = V3.new(cf.X, cf.Y, cf.Z) + dir * (depth or 0)
  return Ray.new(o, dir)
end
CM.Camera.ViewportPointToRay = function(_, x, y, depth) return pixelRay(x, y, depth) end
CM.Camera.ScreenPointToRay = function(_, x, y, depth) return pixelRay(x, y, depth) end
CM.Camera.GetPartsObscuringTarget = function() return {} end
CM.Camera.GetRenderCFrame = function() return camD.props.CFrame end
CM.Camera.Interpolate = function() end
CM.Camera.GetLargestCutoffDistance = function() return 0 end

-- the player's mouse: Hit / Target are computed live from the simulated cursor
CM.Player.GetMouse = function()
  local sigs = {
    Button1Down = X.newSignal("Button1Down"), Button1Up = X.newSignal("Button1Up"),
    Button2Down = X.newSignal("Button2Down"), Button2Up = X.newSignal("Button2Up"),
    Move = X.newSignal("Move"), WheelForward = X.newSignal("WheelForward"), WheelBackward = X.newSignal("WheelBackward"),
    KeyDown = X.newSignal("KeyDown"), KeyUp = X.newSignal("KeyUp"), Idle = X.newSignal("Idle"),
  }
  local function cast()
    local cx, cy = H.cursor()
    local ray = pixelRay(cx, cy, 0)
    local r = raycast(ray.Origin, ray.Direction * 1000, nil)
    return ray, r
  end
  return setmetatable({}, {
    __rbxtype = "Mouse",
    __tostring = function() return "Mouse" end,
    __index = function(_, k)
      if sigs[k] then return sigs[k] end
      if k == "X" then local cx = H.cursor(); return cx end
      if k == "Y" then local _, cy = H.cursor(); return cy end
      if k == "ViewSizeX" then local w = viewSize(); return w end
      if k == "ViewSizeY" then local _, h = viewSize(); return h end
      if k == "Hit" then
        local ray, r = cast()
        if r then return CF.new(r.Position.X, r.Position.Y, r.Position.Z) end
        local p = ray.Origin + ray.Direction * 1000
        return CF.new(p.X, p.Y, p.Z)
      end
      if k == "Target" then local _, r = cast(); return r and r.Instance or nil end
      if k == "UnitRay" then local ray = cast(); return ray end
      if k == "Origin" then local ray = cast(); return CF.new(ray.Origin.X, ray.Origin.Y, ray.Origin.Z) end
      if k == "TargetFilter" then return nil end
      if k == "Icon" then return "" end
      return nil
    end,
    __newindex = function() end,
  })
end

------------------------------------------------------------------------
-- globals and getrenv copies
------------------------------------------------------------------------
G.Ray = Ray
G.RaycastParams = RaycastParams
G.OverlapParams = OverlapParams
X.RENV.Ray = Ray
X.RENV.RaycastParams = RaycastParams
X.RENV.OverlapParams = OverlapParams
X.raycast = raycast

------------------------------------------------------------------------
-- snapshots for the Game tab (plain text, tab separated)
------------------------------------------------------------------------
local function clean(s)
  s = tostring(s):gsub("[\t\r\n|]", " ")
  return s
end

local function f3(n)
  if rawtype(n) ~= "number" or n ~= n then return "0" end
  return string.format("%.3f", n)
end

G.__snapshot = function()
  local lines = {}
  local cf = camD.props.CFrame
  local fov = camD.props.FieldOfView
  lines[#lines + 1] = table.concat({ "C", f3(cf.X), f3(cf.Y), f3(cf.Z), f3(cf.R00), f3(cf.R01), f3(cf.R02), f3(cf.R10), f3(cf.R11),
    f3(cf.R12), f3(cf.R20), f3(cf.R21), f3(cf.R22), f3(rawtype(fov) == "number" and fov or 70) }, "\t")
  lines[#lines + 1] = table.concat({ "S", f3(humD.props.Health), f3(humD.props.MaxHealth), tostring(humD.state or "Running"),
    humD.dead and "1" or "0", f3(hrpD.props.CFrame.X), f3(hrpD.props.CFrame.Y), f3(hrpD.props.CFrame.Z) }, "\t")
  local lt = X.Lighting and D[X.Lighting].props
  local amb = lt and lt.Ambient or C3.new(0.5, 0.5, 0.5)
  lines[#lines + 1] = table.concat({ "L", f3(lt and lt.ClockTime or 14), f3(amb.R), f3(amb.G), f3(amb.B) }, "\t")
  local parts = allParts()
  local count = 0
  for i = 1, #parts do
    local d = parts[i]
    local pcf, sz = d.props.CFrame, d.props.Size
    local tr = d.props.Transparency
    if validCF(pcf) and rawtype(sz) == "table" and sz.X ~= nil and (rawtype(tr) ~= "number" or tr < 1) and count < 700 then
      count = count + 1
      local col = d.props.Color
      if rawtype(col) ~= "table" or col.R == nil then col = C3.new(0.63, 0.64, 0.63) end
      local shape = "0"
      local sh = d.props.Shape
      if rawtype(sh) == "table" and sh.Name == "Ball" then shape = "1" elseif rawtype(sh) == "table" and sh.Name == "Cylinder" then shape = "2" end
      local flags = (d.props.Anchored and 1 or 0) + (d.props.CanCollide ~= false and 2 or 0) + (d.charPart and 4 or 0)
      lines[#lines + 1] = table.concat({ "P", tostring(d.id), clean(d.props.Name), d.class,
        f3(pcf.X), f3(pcf.Y), f3(pcf.Z), f3(sz.X), f3(sz.Y), f3(sz.Z),
        f3(pcf.R00), f3(pcf.R01), f3(pcf.R02), f3(pcf.R10), f3(pcf.R11), f3(pcf.R12), f3(pcf.R20), f3(pcf.R21), f3(pcf.R22),
        f3(col.R), f3(col.G), f3(col.B), f3(rawtype(tr) == "number" and tr or 0), tostring(flags), shape }, "\t")
    end
  end
  return table.concat(lines, "\n")
end

local function findData(id)
  local all = X.ALLDATA
  for i = 1, #all do
    local d = all[i]
    if d.id == id and not d.destroyed then return d end
  end
  return nil
end

G.__explorer = function(csv)
  local open = {}
  for n in string.gmatch(csv or "", "%d+") do open[tonumber(n)] = true end
  local lines = {}
  local function walk(d, depth)
    local ch = d.children
    for i = 1, #ch do
      local cd = D[ch[i]]
      if cd then
        lines[#lines + 1] = table.concat({ tostring(depth), tostring(cd.id), cd.class, clean(cd.props.Name), #cd.children > 0 and "1" or "0" }, "\t")
        if open[cd.id] and #cd.children > 0 and #lines < 1500 then walk(cd, depth + 1) end
      end
    end
  end
  local g = D[X.game]
  lines[#lines + 1] = table.concat({ "0", tostring(g.id), "DataModel", clean(g.props.Name), "1" }, "\t")
  if open[g.id] or true then walk(g, 1) end
  return table.concat(lines, "\n")
end

local function fmtValue(v)
  local tv = X.typeof(v)
  if tv == "Vector3" then return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z), "Vector3", true end
  if tv == "Vector2" then return string.format("%.3f, %.3f", v.X, v.Y), "Vector2", false end
  if tv == "Color3" then
    return string.format("%d, %d, %d", floor(v.R * 255 + 0.5), floor(v.G * 255 + 0.5), floor(v.B * 255 + 0.5)), "Color3", true
  end
  if tv == "CFrame" then return string.format("%.3f, %.3f, %.3f", v.X, v.Y, v.Z), "CFrame", false end
  if tv == "boolean" then return tostring(v), "bool", true end
  if tv == "number" then return tostring(v), "number", true end
  if tv == "string" then return v, "string", true end
  if tv == "EnumItem" then return tostring(v), "Enum", false end
  if tv == "Instance" then return X.fullName(D[v]), "Instance", false end
  if tv == "UDim2" then return string.format("{%g, %g}, {%g, %g}", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset), "UDim2", false end
  return "<" .. tostring(tv) .. ">", tostring(tv), false
end

G.__props = function(id)
  local d = findData(id)
  if not d then return "" end
  local keys = {}
  for k in pairs(d.props) do
    if rawtype(k) == "string" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  local lines = {}
  lines[#lines + 1] = table.concat({ "ClassName", "string", d.class, "0" }, "\t")
  for _, k in ipairs(keys) do
    local v = d.props[k]
    if v ~= nil then
      local s, ty, ed = fmtValue(v)
      lines[#lines + 1] = table.concat({ clean(k), ty, clean(s), ed and "1" or "0" }, "\t")
    end
  end
  local an = {}
  for k, v in pairs(d.attrs or {}) do an[#an + 1] = k end
  table.sort(an)
  for _, k in ipairs(an) do
    local s, ty = fmtValue(d.attrs[k])
    lines[#lines + 1] = table.concat({ "@" .. clean(k), ty, clean(s), "0" }, "\t")
  end
  return table.concat(lines, "\n")
end

G.__setprop = function(id, name, text)
  local d = findData(id)
  if not d then return false, "instance not found" end
  local cur = d.props[name]
  local v
  local tv = X.typeof(cur)
  if tv == "boolean" then
    if text == "true" then v = true elseif text == "false" then v = false else return false, "expected true or false" end
  elseif tv == "number" then
    v = tonumber(text)
    if not v then return false, "expected a number" end
  elseif tv == "string" then
    v = text
  elseif tv == "Vector3" then
    local a, b, c = string.match(text, "^%s*(-?[%d%.eE+-]+)%s*,%s*(-?[%d%.eE+-]+)%s*,%s*(-?[%d%.eE+-]+)%s*$")
    if not a then return false, "expected x, y, z" end
    v = V3.new(tonumber(a), tonumber(b), tonumber(c))
  elseif tv == "Color3" then
    local a, b, c = string.match(text, "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
    if not a then return false, "expected r, g, b (0-255)" end
    v = C3.new(min(255, tonumber(a)) / 255, min(255, tonumber(b)) / 255, min(255, tonumber(c)) / 255)
  else
    return false, "this property type cannot be edited here"
  end
  local ok, err = pcall(function() d.proxy[name] = v end)
  if not ok then return false, tostring(err) end
  return true, ""
end

G.__delete = function(id)
  local d = findData(id)
  if not d then return false end
  if d.class == "DataModel" or d.parent == nil then return false end
  if d.proxy == workspace or d.proxy == charModel then return false end
  local ok = pcall(Methods.Destroy, d.proxy)
  return ok
end

-- one scheduler tick, used by the app while no script is running
G.__tick = function()
  X.step()
end
