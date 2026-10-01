local crypto=ISO.require("system/lib/crypto/init.lua")
local M={}
local ROOT="/.cclua/data/packages"
local REGISTRY=ROOT.."/registry.db"
local MAGIC="CCLUAPKG/1"
local B64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function safeToken(value,label)
  value=tostring(value or "")
  if value=="" or #value>64 or not value:match("^[%w][%w%._%-]*$") then
    return nil,(label or "value").." contains unsafe characters"
  end
  if value=="." or value==".." then return nil,(label or "value").." is unsafe" end
  return value
end

local function safeRel(path)
  if type(path)~="string" or path=="" or path:sub(1,1)=="/" or path:find("\\",1,true) then
    return nil,"unsafe package path"
  end
  if path:find("[%z\1-\31]") then return nil,"unsafe package path" end
  for part in path:gmatch("[^/]+") do
    if part=="." or part==".." or part=="" then return nil,"unsafe package path" end
  end
  return path
end

local function b64decode(data)
  data=tostring(data or ""):gsub("%s+","")
  local out,buffer,bits={},0,0
  for i=1,#data do
    local ch=data:sub(i,i)
    if ch~="=" then
      local v=B64:find(ch,1,true)
      if not v then return nil,"invalid base64" end
      buffer=buffer*64+(v-1);bits=bits+6
      while bits>=8 do
        bits=bits-8
        out[#out+1]=string.char(math.floor(buffer/(2^bits))%256)
      end
      buffer=buffer%(2^bits)
    end
  end
  return table.concat(out)
end

local function ensure()
  if not fs.exists("/.cclua/data") then fs.makeDir("/.cclua/data") end
  if not fs.exists(ROOT) then fs.makeDir(ROOT) end
end

local function loadRegistry()
  ensure()
  if not fs.exists(REGISTRY) then return {packages={},commands={}} end
  local h=fs.open(REGISTRY,"r")
  if not h then return {packages={},commands={}} end
  local raw=h.readAll();h.close()
  local ok,t=pcall(textutils.unserialize,raw)
  if ok and type(t)=="table" then
    t.packages=t.packages or {}
    t.commands=t.commands or {}
    return t
  end
  return {packages={},commands={}}
end

local function saveRegistry(t)
  ensure()
  local h=assert(fs.open(REGISTRY,"w"))
  h.write(textutils.serialize(t,{compact=true}))
  h.close()
end

local function parse(raw)
  local first,rest=raw:match("^([^\r\n]+)[\r\n]+(.*)$")
  if first~=MAGIC then return nil,"invalid package format" end
  local meta,files={},{}
  for line in rest:gmatch("[^\r\n]+") do
    local k,v=line:match("^META%s+([^=]+)=(.*)$")
    if k then
      meta[k]=v
    else
      local p64,sha,d64=line:match("^FILE%s+(%S+)%s+(%x+)%s+(.*)$")
      if p64 then
        local path,err=b64decode(p64)
        if not path then return nil,err end
        local data,derr=b64decode(d64)
        if not data then return nil,derr end
        if crypto.sha256(data,false)~=sha:lower() then
          return nil,"checksum failed: "..path
        end
        files[path]=data
      end
    end
  end
  if not meta.name or not meta.version then return nil,"package metadata incomplete" end
  return {meta=meta,files=files}
end

local function parseCommands(value,files)
  local out={}
  for entry in tostring(value or ""):gmatch("[^;]+") do
    local name,path=entry:match("^([^:]+):(.+)$")
    if not name or not path then return nil,"invalid command mapping" end
    local safeName,nerr=safeToken(name,"command name")
    if not safeName then return nil,nerr end
    local safePath,perr=safeRel(path)
    if not safePath then return nil,perr end
    if files and files[safePath]==nil then return nil,"command target missing: "..safePath end
    out[safeName]=safePath
  end
  return out
end

function M.new(ctx)
  local self={ctx=ctx,registry=loadRegistry()}

  function self:list()
    local out={}
    for name,p in pairs(self.registry.packages) do
      out[#out+1]={
        name=name,version=p.version,installed=p.installed,
        commands=p.commands or {},source=p.source,
      }
    end
    table.sort(out,function(a,b)return a.name<b.name end)
    return out
  end

  function self:findCommand(name)
    return self.registry.commands[name]
  end

  function self:remove(name)
    local p=self.registry.packages[name]
    if not p then return nil,"package not installed" end
    local base=ROOT.."/"..name
    if fs.exists(base) then fs.delete(base) end
    for command,rec in pairs(self.registry.commands) do
      if rec.package==name then self.registry.commands[command]=nil end
    end
    self.registry.packages[name]=nil
    saveRegistry(self.registry)
    return true
  end

  function self:installRaw(raw,source,signature,publicKey)
    if signature and publicKey then
      if not crypto.verify(publicKey,raw,signature) then
        return nil,"package signature rejected"
      end
    end
    local pkg,err=parse(raw)
    if not pkg then return nil,err end
    local name,nerr=safeToken(pkg.meta.name,"package name")
    if not name then return nil,nerr end
    local version,verr=safeToken(pkg.meta.version,"package version")
    if not version then return nil,verr end
    local arch=tostring(pkg.meta.architecture or "any")
    if arch~="any" and arch~=ctx.config.architecture then
      return nil,"package architecture mismatch: "..arch
    end
    for path in pairs(pkg.files) do
      local _,perr=safeRel(path)
      if perr then return nil,perr..": "..tostring(path) end
    end
    local commands,cerr=parseCommands(pkg.meta.commands,pkg.files)
    if not commands then return nil,cerr end
    for command in pairs(commands) do
      local owner=self.registry.commands[command]
      if owner and owner.package~=name then
        return nil,"command already owned by package: "..tostring(owner.package)
      end
    end

    local previousRegistry=loadRegistry()
    ensure()
    local root=ROOT.."/"..name
    local stamp=tostring((os.epoch and os.epoch("utc")) or math.floor(os.clock()*1000))
    local stage=ROOT.."/.stage-"..name.."-"..stamp
    local backup=ROOT.."/.backup-"..name.."-"..stamp
    local base=stage.."/"..version
    if fs.exists(stage) then fs.delete(stage) end
    fs.makeDir(base)
    local wrote,writeErr=pcall(function()
      for path,data in pairs(pkg.files) do
        local target=fs.combine(base,path)
        local dir=fs.getDir(target)
        if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
        local h=assert(fs.open(target,"w"),"cannot create "..target)
        h.write(data);h.close()
      end
    end)
    if not wrote then
      if fs.exists(stage) then fs.delete(stage) end
      return nil,"package staging failed: "..tostring(writeErr)
    end

    local hadPrevious=fs.exists(root)
    local swapped,swapErr=pcall(function()
      if hadPrevious then fs.move(root,backup) end
      fs.move(stage,root)
    end)
    if not swapped then
      if fs.exists(stage) then fs.delete(stage) end
      if fs.exists(backup) and not fs.exists(root) then pcall(fs.move,backup,root) end
      return nil,"package activation failed: "..tostring(swapErr)
    end
    for command,rec in pairs(self.registry.commands) do
      if rec.package==name then self.registry.commands[command]=nil end
    end
    for command,path in pairs(commands) do
      self.registry.commands[command]={
        package=name,version=version,path=path,
      }
    end
    local verified=signature~=nil and publicKey~=nil
    local privileged=(source=="system-image") or
      (verified and (pkg.meta.type=="system-tool" or pkg.meta.type=="driver" or pkg.meta.type=="kernel-extension"))
    self.registry.packages[name]={
      name=name,version=version,installed=os.epoch and os.epoch("utc") or 0,
      source=source or "local",commands=commands,
      description=pkg.meta.description or "",type=pkg.meta.type or "application",
      trusted=verified or source=="system-image",privileged=privileged,
    }
    local saved,saveErr=pcall(saveRegistry,self.registry)
    if not saved then
      self.registry=previousRegistry
      if fs.exists(root) then fs.delete(root) end
      if fs.exists(backup) then pcall(fs.move,backup,root) end
      return nil,"package registry update failed: "..tostring(saveErr)
    end
    if fs.exists(backup) then fs.delete(backup) end
    os.queueEvent("cclua_package_installed",name,version)
    return self.registry.packages[name]
  end

  function self:runCommand(name,args,io)
    local rec=self.registry.commands[name]
    if not rec then return nil,"command not found" end
    local packageName,nerr=safeToken(rec.package,"registry package")
    if not packageName then return nil,nerr end
    local version,verr=safeToken(rec.version,"registry version")
    if not version then return nil,verr end
    local rel,perr=safeRel(rec.path)
    if not rel then return nil,perr end
    local path=ROOT.."/"..packageName.."/"..version.."/"..rel
    if not fs.exists(path) then return nil,"package command missing" end
    local h=fs.open(path,"r");if not h then return nil,"cannot open command" end
    local source=h.readAll();h.close()
    io=io or {}
    local function emit(...)
      local t={}
      for i=1,select("#",...) do t[#t+1]=tostring(select(i,...)) end
      local s=table.concat(t," ")
      if io.write then io.write(s.."\n") else print(s) end
    end
    local env=setmetatable({
      CCLUA={ctx=ctx,io=io,package=rec.package,command=name},
      print=emit,
      write=function(s) if io.write then io.write(tostring(s)) else write(tostring(s)) end end,
    },{__index=_G})
    local fn,err=load(source,"@"..path,"t",env)
    if not fn then return nil,err end
    local ok,result=pcall(fn)
    if not ok then return nil,result end
    if type(result)=="function" then
      local rok,r=pcall(result,args or {},io,ctx)
      if not rok then return nil,r end
      return true,r
    elseif type(result)=="table" and type(result.main)=="function" then
      local rok,r=pcall(result.main,args or {},io,ctx)
      if not rok then return nil,r end
      return true,r
    end
    return true,result
  end

  return self
end

M.ROOT=ROOT
M.MAGIC=MAGIC
return M
