local Http = {}
Http.__index = Http

function Http.new(components, fs, options)
  options = options or {}
  return setmetatable({components=components,fs=fs,maxBytes=options.maxBytes or 4194304,
    pollDelay=options.pollDelay or 0.05,logger=options.logger},Http)
end

function Http:_internetAddress()
  for address in self.components:list("internet") do return address end
end

local function close(request)
  if request and type(request.close)=="function"then pcall(request.close)end
end

function Http:download(url,target,options,api)
  options=options or{};api=api or{sleep=function()end}
  if type(url)~="string"or not url:match("^https?://")then return nil,"HTTP(S) URL required"end
  local address=self:_internetAddress();if not address then return nil,"Internet Card unavailable"end
  if self.fs.exists(target)and not options.force then return nil,"file already exists"end
  local ok,request,reason=self.components:invoke(address,"request",url,options.data,
    options.headers or{["User-Agent"]="PlasmaOS/0.1"},options.method)
  if not ok or not request then return nil,reason or request or"request failed"end
  local parentOk,parentErr=self.fs.makeParent(target);if not parentOk then close(request);return nil,parentErr end
  local handle,openErr=self.fs.open(target,"wb");if not handle then close(request);return nil,openErr end
  local total,limit=0,options.maxBytes or self.maxBytes
  while true do
    local read={pcall(request.read,math.huge)}
    if not read[1]then handle:close();close(request);self.fs.remove(target);return nil,read[2]end
    local chunk,readErr=read[2],read[3]
    if chunk==nil then
      handle:close();close(request)
      if readErr then self.fs.remove(target);return nil,readErr end
      return true,total
    elseif #chunk==0 then api.sleep(self.pollDelay)
    else
      total=total+#chunk;if total>limit then handle:close();close(request);self.fs.remove(target);return nil,"download exceeds size limit"end
      local wrote,writeErr=handle:write(chunk);if not wrote then handle:close();close(request);self.fs.remove(target);return nil,writeErr end
      api.sleep(0)
    end
  end
end

return Http
