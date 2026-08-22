local Builtins = {}

local function charFrom(event, unicode)
  if not event.char or event.char <= 0 then return nil end
  if unicode and unicode.char then return unicode.char(event.char) end
  if event.char < 256 then return string.char(event.char) end
end

local function row(text, options) options=options or{};options.text=tostring(text or"");return options end
local function toolbar(labels)
  local segments={}
  for index,label in ipairs(labels)do
    local value=type(label)=="table"and label or{text=label}
    segments[#segments+1]={text=" "..tostring(value.text or"").." ",
      primary=value.primary~=nil and value.primary or index==1,
      role=value.role,backgroundRole=value.backgroundRole,disabled=value.disabled}
  end
  return row("",{style="toolbar",segments=segments,pad=false})
end
local function buttonAt(labels,x)
  local position=2
  for index,label in ipairs(labels)do
    local text=type(label)=="table"and label.text or label;local width=#tostring(text or"")+2
    if x>=position and x<position+width then return index end;position=position+width+1
  end
end
local function clamp(value,low,high)return math.max(low,math.min(high,value))end
local function tail(value,size)value=tostring(value or"");return #value>size and value:sub(-size)or value end
local function nameOf(path)return path:match("([^/]+)$")or path end
local function emptyState(title,message)return{row(""),row("  "..title,{role="accent"}),row("  "..message,{role="secondary"}),row("  Connect compatible hardware, then choose Refresh.",{role="secondary"})}end

local function explorer(context)
  local s=context.services
  local m={path=context.options.path or"/home/player",hidden=false,selected=1,scroll=1,entries={},status="Ready"}
  function m:refresh()
    local entries,err=s.files:list(self.path,self.hidden);self.entries=entries or{}
    self.status=err and tostring(err)or(#self.entries.." items");self.selected=clamp(self.selected,1,math.max(1,#self.entries))
  end
  function m:open()
    local item=self.entries[self.selected];if not item then return end
    if item.directory then self.path=item.path;self.selected,self.scroll=1,1;self:refresh()
    else s.apps:launch("editor",context.session.id,{services=s,path=item.path})end
  end
  function m:up()local parent=self.path:match("^(.*)/[^/]+/?$")or"/";self.path=parent==""and"/"or parent;self.selected,self.scroll=1,1;self:refresh()end
  function m:render(width,height)
    local buttons={"Up","Open","New file","Hidden "..(self.hidden and"ON"or"OFF"),"Refresh"}
    local out={row("  "..self.path,{style="header",pad=false}),toolbar(buttons),
      row(string.format("  %-7s %-"..math.max(10,width-25).."s %s","TYPE","NAME","ACCESS"),{backgroundRole="field",role="secondary",pad=false})}
    local room=math.max(1,height-4);if self.selected<self.scroll then self.scroll=self.selected end;if self.selected>=self.scroll+room then self.scroll=self.selected-room+1 end
    for index=self.scroll,math.min(#self.entries,self.scroll+room-1)do local item=self.entries[index];local kind=item.directory and"Folder"or((item.name:match("%.([^%.]+)$")or"File"):upper())
      out[#out+1]=row(string.format("  %-7s %-"..math.max(10,width-25).."s %s",kind:sub(1,7),item.name:sub(1,math.max(10,width-25)),item.readOnly and"Read only"or"Writable"),{selected=index==self.selected,pad=false})end
    if #self.entries==0 then out[#out+1]=row("  This folder is empty",{role="secondary"})end
    out[#out+1]=row("  "..self.status.."   Enter: open   Backspace: up   Del: trash",{style="status",pad=false});return out
  end
  function m:onEvent(event)
    if event.name=="key_down"then local ch=charFrom(event,s.unicode);ch=ch and ch:lower()
      if event.code==200 then self.selected=math.max(1,self.selected-1)elseif event.code==208 then self.selected=math.min(#self.entries,self.selected+1)
      elseif event.code==28 then self:open()elseif event.code==14 then self:up()
      elseif event.code==211 then local item=self.entries[self.selected];if item then local ok,err=s.files:trashPath(item.path);self.status=ok and("Moved "..item.name.." to Trash")or tostring(err);self:refresh()end
      elseif ch=="h"then self.hidden=not self.hidden;self:refresh()elseif ch=="r"then self:refresh()
      elseif ch=="n"then local ok,err=s.files:createFile(s.fs.concat(self.path,"New File.lua"));self.status=ok and"Created New File.lua"or tostring(err);self:refresh()end
    elseif event.name=="touch"and event.localY==2 then local action=buttonAt({"Up","Open","New file","Hidden "..(self.hidden and"ON"or"OFF"),"Refresh"},event.localX)
      if action==1 then self:up()elseif action==2 then self:open()elseif action==3 then local ok,err=s.files:createFile(s.fs.concat(self.path,"New File.lua"));self.status=ok and"Created New File.lua"or tostring(err);self:refresh()elseif action==4 then self.hidden=not self.hidden;self:refresh()elseif action==5 then self:refresh()end
    elseif event.name=="touch"and event.localY>=4 then local index=self.scroll+event.localY-4;if self.entries[index]then self.selected=index end
    elseif event.name=="scroll"then self.selected=clamp(self.selected+(event.button or 0),1,math.max(1,#self.entries))end
  end
  m:refresh();return m
end

local function terminal(context)
  local s=context.services;local m={input="",output={"PlasmaOS command console","Type help to see available commands."},history={},historyIndex=1}
  function m:render(width,height)local out={row("  Command Console",{style="header",pad=false}),row("  Session: "..context.session.user.."    History: "..#self.history,{style="toolbar",pad=false})};local room=math.max(1,height-4)
    for i=math.max(1,#self.output-room+1),#self.output do out[#out+1]=row("  "..tostring(self.output[i]):sub(1,math.max(1,width-2)),{backgroundRole="field",pad=false})end
    out[#out+1]=row("  > "..self.input.."_",{backgroundRole="field",role="accent",pad=false});out[#out+1]=row("  Enter: run    Up/Down: history    Paste supported",{style="status",pad=false});return out end
  function m:onEvent(event)if event.name=="clipboard"then self.input=self.input..(event.text or"")elseif event.name=="key_down"then
      if event.code==14 then self.input=self.input:sub(1,-2)elseif event.code==28 then local line=self.input;self.output[#self.output+1]="> "..line;if line~=""then self.history[#self.history+1]=line;self.historyIndex=#self.history+1 end
        local ok,result=pcall(s.shell.execute,s.shell,line,context.session);if not ok then result={"error: "..tostring(result)}end
        if result.__clear then self.output={}else for _,value in ipairs(result)do for text in tostring(value):gmatch("[^\n]+")do self.output[#self.output+1]=text end end end
        while #self.output>160 do table.remove(self.output,1)end;self.input=""
      elseif event.code==200 and#self.history>0 then self.historyIndex=math.max(1,self.historyIndex-1);self.input=self.history[self.historyIndex]
      elseif event.code==208 and#self.history>0 then self.historyIndex=math.min(#self.history+1,self.historyIndex+1);self.input=self.history[self.historyIndex]or""
      else local ch=charFrom(event,s.unicode);if ch and ch:byte()>=32 then self.input=self.input..ch end end end end;return m
end

local function taskManager(context)
  local s=context.services;local m={tab=1,selected=1,refreshInterval=.75};local names={"Processes","Performance","Services","Hardware","Sessions","Logs"}
  function m:render(width,height)local tabs={};for index,name in ipairs(names)do tabs[index]={text=name,primary=index==self.tab}end;local out={row("  System Monitor",{style="header",pad=false}),toolbar(tabs),row("  "..names[self.tab].."    1-6: views    K: end/restart",{backgroundRole="field",role="accent",pad=false})}
    if self.tab==1 then out[#out+1]=row("  PID   STATE       APPLICATION        PROCESS",{role="secondary"});for i,p in ipairs(s.scheduler:list())do out[#out+1]=row(string.format("  %3d   %-10s  %-17s  %s",p.pid,p.state,p.appId:sub(1,17),p.name),{selected=i==self.selected})end
    elseif self.tab==2 then local mem=s.memory:sample();local used=math.max(0,mem.total-mem.free);out[#out+1]=row(string.format("  Memory     %d used / %d total     %s",used,mem.total,mem.state),{style=mem.state=="normal"and"success"or"danger"});out[#out+1]=row(string.format("  Scheduler  cycle %d     ready queue %d",s.scheduler.cycle,s.scheduler.ready:size()),{backgroundRole="raised"});for _,e in ipairs(s.registry:list())do local x=s.compositor:metrics(e.id);out[#out+1]=row(string.format("  Display    %dx%d     frames %d     queue %d     errors %d",e.width,e.height,x.renderedFrames,x.queueDepth,x.componentErrors))end
    elseif self.tab==3 then out[#out+1]=row("  SERVICE                    STATE        RESTARTS",{role="secondary"});for i,v in ipairs(s.supervisor:list())do out[#out+1]=row(string.format("  %-26s %-12s %d",v.id,v.state,v.restartCount),{selected=i==self.selected})end
    elseif self.tab==4 then out[#out+1]=row("  ADDRESS       COMPONENT                 METHODS",{role="secondary"});for i,v in ipairs(s.components:snapshot())do out[#out+1]=row(string.format("  %-12s  %-24s  %d",v.address:sub(1,12),v.type,#v.methods),{selected=i==self.selected})end
    elseif self.tab==5 then for i,v in ipairs(s.sessions:list())do local e=s.registry:get(v.endpointId);out[#out+1]=row(string.format("  %-12s %-9s  %dx%d  input queue %d",v.id,v.state,e and e.width or 0,e and e.height or 0,v.inputQueueDepth),{selected=i==self.selected})end
    else local logs=s.log:list();for i=math.max(1,#logs-math.max(1,height-4)),#logs do local v=logs[i];out[#out+1]=row(string.format("  %-7s %-12s %s",v.level,v.source,v.message),{role=v.level=="error"and"error"or"foreground"})end end
    out[#out+1]=row("  Live data   refresh 0.75 s",{style="status",pad=false});return out end
  function m:onEvent(event)if event.name=="touch"and event.localY==2 then local tab=buttonAt(names,event.localX);if tab then self.tab,self.selected=tab,1 end;return elseif event.name~="key_down"then return end;local ch=charFrom(event,s.unicode);local number=ch and tonumber(ch);if number and number>=1 and number<=6 then self.tab,self.selected=number,1 elseif event.code==200 then self.selected=math.max(1,self.selected-1)elseif event.code==208 then self.selected=self.selected+1 elseif ch and ch:lower()=="k"then if self.tab==1 then local v=s.scheduler:list()[self.selected];if v and v.pid~=context.api.pid()then s.scheduler:kill(v.pid,"System Monitor")end elseif self.tab==5 then local v=s.sessions:list()[self.selected];if v then s.sessions:restart(v.id)end end end end
  function m:tick()end;return m
end

local settingPages={{"Appearance","Theme and visual contrast"},{"Desktop","Panel and desktop behavior"},{"Display","Resolution and refresh"},{"Performance","Remote display bandwidth"},{"Input","Keyboard and pointer"},{"Security","Users and session lock"},{"Services","Startup and background services"},{"Network","Modems and remote nodes"},{"Updates","Packages and core releases"},{"Notifications","Alerts and quiet mode"},{"Time","Clock and time display"},{"GTNH","Machine integration adapters"},{"Accessibility","Contrast and readable layouts"},{"Developer","Diagnostics and overlay"},{"Recovery","Backups and rollback"}}
local function settings(context)
  local s=context.services;local m={selected=1,status="Settings are saved immediately"}
  function m:render()local out={row("  System Settings",{style="header",pad=false}),row("  Personalize and manage this computer",{style="toolbar",pad=false}),row(string.format("  %-20s  %s","CATEGORY","DETAILS"),{backgroundRole="field",role="secondary"})}
    for i,item in ipairs(settingPages)do local detail="";if i==self.selected then if i==1 then detail="Theme: "..context.session.theme.."  (Enter to change)"elseif i==3 then local e=s.registry:get(context.session.endpointId);detail=string.format("Native %dx%d at %d FPS",e.width,e.height,e.targetFps)elseif i==4 then local e=s.registry:get(context.session.endpointId);detail="Low bandwidth: "..(e.lowBandwidth and"enabled"or"disabled").."  (Enter to toggle)"elseif i==6 then detail="Ctrl+L locks the current session"elseif i==10 then detail="Do not disturb: "..(s.notifications.doNotDisturb and"enabled"or"disabled").."  (Enter to toggle)"elseif i==14 then detail="F12 toggles the live diagnostics overlay"else detail=item[2]end end;out[#out+1]=row(string.format("  %-20s  %s",item[1],detail),{selected=i==self.selected})end
    out[#out+1]=row("  "..self.status.."    Up/Down: select    Enter: change",{style="status",pad=false});return out end
  function m:onEvent(event)if event.name=="touch"and event.localY>=4 then self.selected=clamp(event.localY-3,1,#settingPages)elseif event.name=="key_down"then if event.code==200 then self.selected=math.max(1,self.selected-1)elseif event.code==208 then self.selected=math.min(#settingPages,self.selected+1)elseif event.code==28 and self.selected==1 then local order={"dark","light","highContrast","lowColor"};local nextIndex=1;for i,name in ipairs(order)do if name==context.session.theme then nextIndex=i%#order+1 end end;context.session.theme=order[nextIndex];local config=s.config:load("desktop");config.theme=context.session.theme;s.config:save("desktop",config);s.desktop:request(context.session);self.status="Theme changed to "..context.session.theme elseif event.code==28 and self.selected==4 then local e=s.registry:get(context.session.endpointId);e.lowBandwidth=not e.lowBandwidth;e.targetFps=e.lowBandwidth and 4 or 12;self.status="Performance profile updated"elseif event.code==28 and self.selected==10 then s.notifications.doNotDisturb=not s.notifications.doNotDisturb;self.status="Notification mode updated"end end end;return m
end

local function editor(context)
  local s,path=context.services,context.options.path or"/home/player/untitled.lua";local data=s.fs.read(path)or"";local m={path=path,lines={},row=1,column=1,scroll=1,undo={},redo={},status="Ready"};for line in(data.."\n"):gmatch("(.-)\n")do m.lines[#m.lines+1]=line end;if#m.lines==0 then m.lines[1]=""end
  function m:snapshot()local v=table.concat(self.lines,"\n");self.undo[#self.undo+1]=v;if#self.undo>64 then table.remove(self.undo,1)end;self.redo={}end
  function m:save()local ok,err=s.transaction:write(self.path,table.concat(self.lines,"\n"),function()return true end);self.status=ok and"Saved successfully"or("Save failed: "..tostring(err))end
  function m:undoOnce()if#self.undo==0 then return end;self.redo[#self.redo+1]=table.concat(self.lines,"\n");local value=table.remove(self.undo);self.lines={};for line in(value.."\n"):gmatch("(.-)\n")do self.lines[#self.lines+1]=line end;self.status="Undo applied"end
  function m:render(width,height)local out={row("  "..nameOf(self.path).."  -  Plasma Editor",{style="header",pad=false}),toolbar({"Save","Undo","Find"})};local room=math.max(1,height-3);if self.row<self.scroll then self.scroll=self.row end;if self.row>=self.scroll+room then self.scroll=self.row-room+1 end;for i=self.scroll,math.min(#self.lines,self.scroll+room-1)do local mark=i==self.row and">"or" ";local text=self.lines[i];if i==self.row then text=text:sub(1,self.column-1).."|"..text:sub(self.column)end;out[#out+1]=row(string.format(" %s%4d  %s",mark,i,text:sub(1,math.max(1,width-9))),{selected=i==self.row,backgroundRole="field",pad=false})end;out[#out+1]=row(string.format("  Ln %d, Col %d    %s    Ctrl+S save",self.row,self.column,self.status),{style="status",pad=false});return out end
  function m:onEvent(event)if event.name=="touch"and event.localY==2 then local action=buttonAt({"Save","Undo","Find"},event.localX);if action==1 then self:save()elseif action==2 then self:undoOnce()elseif action==3 then self.status="Find is available with Ctrl+F"end;return elseif event.name~="key_down"then return end;local mods=s.desktop.modifiers[context.session.id]or{};local ch=charFrom(event,s.unicode);if mods.ctrl and ch and ch:lower()=="s"then self:save();return end;if mods.ctrl and ch and ch:lower()=="z"then self:undoOnce();return end;if event.code==200 then self.row=math.max(1,self.row-1);self.column=math.min(self.column,#self.lines[self.row]+1)elseif event.code==208 then self.row=math.min(#self.lines,self.row+1);self.column=math.min(self.column,#self.lines[self.row]+1)elseif event.code==203 then self.column=math.max(1,self.column-1)elseif event.code==205 then self.column=math.min(#self.lines[self.row]+1,self.column+1)elseif event.code==14 then self:snapshot();local line=self.lines[self.row];if self.column>1 then self.lines[self.row]=line:sub(1,self.column-2)..line:sub(self.column);self.column=self.column-1 end elseif event.code==28 then self:snapshot();local line=self.lines[self.row];local rest=line:sub(self.column);self.lines[self.row]=line:sub(1,self.column-1);table.insert(self.lines,self.row+1,rest);self.row,self.column=self.row+1,1 elseif ch and ch:byte()>=32 then self:snapshot();local line=self.lines[self.row];self.lines[self.row]=line:sub(1,self.column-1)..ch..line:sub(self.column);self.column=self.column+#ch end end;return m
end

local function dataApp(spec)
  return function(context)local m={selected=1,refreshInterval=spec.interval or 2,status="Live"}
    function m:items()
      local ok,items=pcall(spec.provider,context.services,context)
      if ok then return items,nil end
      return {},items
    end
    function m:render()local items,err=self:items();local buttons={"Refresh","Details"};if spec.actionLabel then buttons[#buttons+1]=spec.actionLabel end;local out={row("  "..spec.title,{style="header",pad=false}),toolbar(buttons)};if err then out[#out+1]=row("  Data source error: "..tostring(err),{style="danger"})elseif#items==0 then for _,v in ipairs(emptyState(spec.emptyTitle or"Nothing to show",spec.emptyMessage or"No data is currently available."))do out[#out+1]=v end else out[#out+1]=row("  "..(spec.columns or"NAME                         STATUS          DETAIL"),{backgroundRole="field",role="secondary"});for i,item in ipairs(items)do local text=type(item)=="table"and(item.text or table.concat(item,"   "))or tostring(item);out[#out+1]=row("  "..text,{selected=i==self.selected})end end;out[#out+1]=row("  "..self.status.."    Up/Down: select    Enter: action",{style="status",pad=false});return out end
    function m:runAction()if not spec.action then self.status="No action is available for this view";return end;local items=self:items();local ok,result=spec.action(context.services,context,items[self.selected]);self.status=ok and tostring(result or"Action completed")or tostring(result)end
    function m:onEvent(event)if event.name=="key_down"then if event.code==200 then self.selected=math.max(1,self.selected-1)elseif event.code==208 then self.selected=self.selected+1 elseif event.code==28 then self:runAction()end elseif event.name=="touch"and event.localY==2 then local buttons={"Refresh","Details"};if spec.actionLabel then buttons[#buttons+1]=spec.actionLabel end;local action=buttonAt(buttons,event.localX);if action==1 then self.status="Data refreshed"elseif action==2 then self.status="Select a row to inspect its details"elseif action==3 then self:runAction()end elseif event.name=="touch"and event.localY>=4 then self.selected=math.max(1,event.localY-3)end end
    function m:tick()end;return m end
end

local function integrationRows(s,matcher)local out={};for _,item in ipairs(s.integrations:list())do local value=(item.adapter.." "..item.type):lower();if not matcher or matcher(value)then out[#out+1]={tail(item.address,12),item.type:sub(1,22),item.state,item.lastError or"Ready"}end end;return out end

function Builtins.register(apps)
  apps:register({id="files",name="File Explorer",category="System",essential=true,width=92,height=26,minWidth=42,minHeight=12},explorer)
  apps:register({id="terminal",name="Command Console",category="System",essential=true,width=94,height=27,minWidth=42,minHeight=12},terminal)
  apps:register({id="tasks",name="System Monitor",category="System",essential=true,width=104,height=29,minWidth=52,minHeight=14},taskManager)
  apps:register({id="settings",name="System Settings",category="System",width=100,height=28,minWidth=52,minHeight=16},settings)
  apps:register({id="editor",name="Plasma Editor",category="Development",width=104,height=30,minWidth=48,minHeight=14},editor)
  apps:register({id="components",name="Component Explorer",category="Development",width=96,height=25,minWidth=44,minHeight=12},dataApp({title="Component Explorer",columns="ADDRESS       TYPE                       METHODS",emptyTitle="No components detected",emptyMessage="The runtime did not report any OpenComputers components.",provider=function(s)local out={};for _,item in ipairs(s.components:snapshot())do out[#out+1]={item.address:sub(1,12),item.type:sub(1,26),"methods "..#item.methods}end;return out end}))
  apps:register({id="machines",name="Machine Dashboard",category="GTNH",width=98,height=26,minWidth=46,minHeight=12},dataApp({title="Machine Dashboard",columns="ADDRESS       ADAPTER                    STATE           DETAIL",emptyTitle="No machines connected",emptyMessage="Attach an adapter or compatible machine component.",provider=function(s)return integrationRows(s,function(v)return not v:find("generic",1,true)end)end}))
  local centers={{"energy","Energy Center",{"energy","power","battery"},"No energy network detected","Connect power storage or monitoring components."},{"inventory","Inventory & Fluids",{"inventory","tank","fluid","transposer"},"No storage network detected","Connect inventory controllers, tanks, or transposers."},{"redstone","Redstone Control",{"redstone"},"No redstone I/O detected","Install a redstone card or attach managed I/O."},{"base","Base Control",{"base","environment","sensor"},"No base sensors detected","Connect environmental and facility sensors."},{"ae","AE / ME Center",{"ae","me","applied"},"No ME network detected","Attach an Applied Energistics network adapter."},{"gregtech","GregTech Machines",{"gregtech","machine","gt_"},"No GregTech machines detected","Expose machine components through a compatible adapter."},{"reactor","Reactor & Plant",{"reactor","turbine","boiler"},"No plant controller detected","Connect reactor, turbine, or boiler monitoring hardware."},{"network","Network & Racks",{"modem","server","rack","network"},"No managed network devices","Install a modem or connect a server rack."},{"robots","Robot & Drone Console",{"robot","drone"},"No robots online","Pair robots or drones with this control network."},{"navigation","World & Navigation",{"navigation","geolyzer","waypoint","gps"},"No navigation hardware detected","Connect a navigation upgrade, geolyzer, or waypoint source."}}
  for _,center in ipairs(centers)do local id,title,keys,emptyTitle,emptyMessage=center[1],center[2],center[3],center[4],center[5];apps:register({id=id,name=title,category="GTNH",width=98,height=26,minWidth=46,minHeight=12},dataApp({title=title,columns="ADDRESS       DEVICE                     STATE           DETAIL",emptyTitle=emptyTitle,emptyMessage=emptyMessage,provider=function(s)return integrationRows(s,function(value)for _,key in ipairs(keys)do if value:find(key,1,true)then return true end end end)end}))end
  apps:register({id="packages",name="Application Center",category="System",width=90,height=24,minWidth=44,minHeight=12},dataApp({title="Application Center",columns="APPLICATION                    VERSION        STATUS",emptyTitle="No optional applications installed",emptyMessage="Core applications are built in; signed packages appear here.",provider=function(s)local out={};for id,item in pairs(s.packages.installed)do out[#out+1]={id,item.version,"Installed"}end;table.sort(out,function(a,b)return a[1]<b[1]end);return out end}))
  apps:register({id="automation",name="Automation Scheduler",category="GTNH",width=92,height=24,minWidth=44,minHeight=12},dataApp({title="Automation Scheduler",columns="JOB                           STATE          FAILURES",actionLabel="Run now",emptyTitle="No automation jobs",emptyMessage="Scheduled and event-driven jobs will appear here.",provider=function(s)local out={};for _,job in ipairs(s.automation:list())do out[#out+1]={job.id,job.running and"Running"or(job.enabled and"Scheduled"or"Disabled"),"failures "..job.failures,_id=job.id}end;return out end,action=function(s,_,item)if not item then return nil,"Select a job first"end;local ok,err=s.automation:manual(item._id);return ok,ok and"Job started"or err end}))
  apps:register({id="notifications",name="Notification Center",category="System",width=92,height=24,minWidth=44,minHeight=12},dataApp({title="Notification Center",columns="LEVEL      SOURCE             TITLE                         STATE",actionLabel="Acknowledge",emptyTitle="You're all caught up",emptyMessage="System and machine alerts will collect here.",provider=function(s)local out={};local items=s.notifications:list();for i=#items,1,-1 do local item=items[i];out[#out+1]={item.severity,item.source,item.title,item.acknowledged and"Acknowledged"or"New",_id=item.id}end;return out end,action=function(s,c,item)if not item then return nil,"Select a notification first"end;local ok,err=s.notifications:acknowledge(item._id,c.session.user);return ok,ok and"Notification acknowledged"or err end}))
end

return Builtins
