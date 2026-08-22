local Sha256 = require("libs.sha256")

local Update = {}
Update.__index = Update

function Update.new(scheduler, fs, packages, options)
  options = options or {}
  return setmetatable({scheduler=scheduler,fs=fs,packages=packages,state="idle",
    progress=0,error=nil,jobPid=nil,cancelled=false,root=options.root or "/system/versions"},Update)
end

function Update:_atomic(path,value)
  local fresh,backup=path..".new",path..".bak"
  assert(self.fs.write(fresh,value));self.fs.remove(backup)
  if self.fs.exists(path)then assert(self.fs.rename(path,backup))end
  local ok,err=self.fs.rename(fresh,path)
  if not ok then if self.fs.exists(backup)then self.fs.rename(backup,path)end;return nil,err end
  return true
end

function Update:stage(manifest, fetcher, activate)
  if self.state=="downloading" then return nil,"update already running" end
  assert(manifest.version and type(manifest.files)=="table","invalid update manifest")
  self.state,self.progress,self.error,self.cancelled="downloading",0,nil,false
  self.jobPid=self.scheduler:spawn(function(api)
    local staging=self.fs.concat(self.root,".staging-"..manifest.version)
    self.fs.removeTree(staging);assert(self.fs.makeDirectory(staging))
    for index,file in ipairs(manifest.files)do
      if self.cancelled or api.cancelled()then self.fs.removeTree(staging);self.state="cancelled";return end
      assert(file.path and not ("/"..file.path.."/"):find("/../",1,true) and file.path:sub(1,1)~="/","unsafe update path")
      local data,err=fetcher(file.path,file)
      assert(data,"download failed: "..file.path..": "..tostring(err))
      assert(#data==file.size,"size mismatch: "..file.path)
      assert(Sha256.digest(data)==file.sha256,"checksum mismatch: "..file.path)
      local target=self.fs.concat(staging,file.path);assert(self.fs.makeParent(target));assert(self.fs.write(target,data))
      self.progress=index/#manifest.files;api.yield()
    end
    assert(self.fs.write(self.fs.concat(staging,".complete"),manifest.version))
    local final=self.fs.concat(self.root,manifest.version);assert(not self.fs.exists(final),"version already installed")
    assert(self.fs.rename(staging,final));self.state="staged"
    if activate then
      local current=self.fs.read("/system/active")
      if current then assert(self:_atomic("/system/last-good",current))end
      assert(self:_atomic("/system/active",manifest.version));assert(self:_atomic("/system/boot-attempts","0"))
      self.state="pending-reboot"
    end
  end,{name="core-update:"..manifest.version,appId="update",owner="system",onExit=function(_,state,detail)
    self.jobPid=nil
    if state=="crashed"then self.state,self.error="failed",tostring(detail)end
  end})
  return self.jobPid
end

function Update:cancel() self.cancelled=true;return true end
function Update:status() return{state=self.state,progress=self.progress,error=self.error,pid=self.jobPid}end
function Update:rollback()
  local previous=self.fs.read("/system/last-good");if not previous then return nil,"no last-known-good version"end
  assert(self:_atomic("/system/active",previous));assert(self:_atomic("/system/boot-attempts","0"));self.state="rollback-pending"
  return true
end

return Update
