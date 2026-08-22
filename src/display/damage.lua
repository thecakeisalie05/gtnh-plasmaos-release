local Damage = {}
Damage.__index = Damage

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function normalize(rect, width, height)
  local x = clamp(math.floor(rect.x or 1), 1, width)
  local y = clamp(math.floor(rect.y or 1), 1, height)
  local right = clamp(x + math.max(0, math.floor(rect.w or 0)) - 1, 0, width)
  local bottom = clamp(y + math.max(0, math.floor(rect.h or 0)) - 1, 0, height)
  if right < x or bottom < y then return nil end
  return {x = x, y = y, w = right - x + 1, h = bottom - y + 1}
end

local function touches(a, b)
  return a.x <= b.x + b.w and b.x <= a.x + a.w
    and a.y <= b.y + b.h and b.y <= a.y + a.h
end

local function union(a, b)
  local x, y = math.min(a.x, b.x), math.min(a.y, b.y)
  local right = math.max(a.x + a.w - 1, b.x + b.w - 1)
  local bottom = math.max(a.y + a.h - 1, b.y + b.h - 1)
  return {x = x, y = y, w = right - x + 1, h = bottom - y + 1}
end

function Damage.new(width, height, maxRegions)
  return setmetatable({width = width, height = height, maxRegions = maxRegions or 12,
    regions = {}, full = false}, Damage)
end

function Damage:add(rect)
  if self.full then return end
  local candidate = normalize(rect, self.width, self.height)
  if not candidate then return end
  local changed = true
  while changed do
    changed = false
    for index = #self.regions, 1, -1 do
      if touches(candidate, self.regions[index]) then
        candidate = union(candidate, self.regions[index])
        table.remove(self.regions, index); changed = true
      end
    end
  end
  self.regions[#self.regions + 1] = candidate
  if #self.regions > self.maxRegions then
    self.regions = {{x = 1, y = 1, w = self.width, h = self.height}}
    self.full = true
  end
end

function Damage:take()
  local regions = self.regions
  self.regions, self.full = {}, false
  return regions
end

function Damage:count() return #self.regions end

return Damage
