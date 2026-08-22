local Capabilities = {}
Capabilities.__index = Capabilities

function Capabilities.new(audit)
  return setmetatable({grants = {}, audit = audit}, Capabilities)
end

function Capabilities:grant(subject, capability)
  self.grants[subject] = self.grants[subject] or {}
  self.grants[subject][capability] = true
end

function Capabilities:revoke(subject, capability)
  if self.grants[subject] then self.grants[subject][capability] = nil end
end

function Capabilities:has(subject, capability)
  local grants = self.grants[subject]
  return grants and (grants[capability] or grants["*"]) or false
end

function Capabilities:require(subject, capability, context)
  local allowed = self:has(subject, capability)
  if self.audit then self.audit(subject, capability, allowed, context) end
  if not allowed then return nil, "capability denied: " .. capability end
  return true
end

return Capabilities
