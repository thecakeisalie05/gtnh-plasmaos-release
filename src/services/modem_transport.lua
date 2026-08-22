local Json=require("libs.json")

local Modem={}
Modem.__index=Modem

function Modem.new(components,network,options)
  options=options or{}
  return setmetatable({components=components,network=network,port=options.port or 43770,
    address=nil,logger=options.logger},Modem)
end

function Modem:discover()
  self.address=nil
  for address in self.components:list("modem")do self.address=address;break end
  if not self.address then return nil,"modem unavailable" end
  local ok,err=self.components:invoke(self.address,"open",self.port)
  if not ok then self.address=nil;return nil,err end
  return self.address
end

function Modem:send(envelope)
  if not self.address then local ok,err=self:discover();if not ok then return nil,err end end
  local ok,err=self.components:invoke(self.address,"broadcast",self.port,Json.encode(envelope))
  if not ok then self.address=nil;return nil,err end
  return true
end

function Modem:receive(event)
  if event.name~="modem_message"or event.args[3]~=self.port then return false end
  local payload=event.args[5]
  if type(payload)~="string"then return nil,"invalid modem payload"end
  local ok,envelope=pcall(Json.decode,payload);if not ok then return nil,envelope end
  return self.network:receive(envelope)
end

return Modem
