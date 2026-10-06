local config=dofile("/usr/lib/cclua/config.lua")
local net=dofile("/usr/lib/cclua/net.lua")
local protocol="cclua-apphost-v1"

local function usage()
  print("Usage:")
  print("  cclua-appctl status|list")
  print("  cclua-appctl info <app>")
  print("  cclua-appctl start <app>")
  print("  cclua-appctl stop <app>")
  print("  cclua-appctl restart <app>")
  print("  cclua-appctl deploy <app> [source] [--start]")
  print("  cclua-appctl rollback <app>")
  print("  cclua-appctl remove <app>")
end

local function host(path) return tostring(path):gsub("^/","") end

local function print_state(state)
  if type(state)~="table" then return end
  print(("App host: %s (ID %s)"):format(state.hostname or "-",state.computer_id or "-"))
  local apps=state.apps or {}
  if #apps==0 then print("(no apps installed)") end
  for _,a in ipairs(apps) do
    local version=a.version and (" version="..tostring(a.version)) or ""
    local compat=a.compatible==false and " incompatible" or ""
    print(("  %-24s %-8s pid=%s%s%s"):format(
      a.name or "-",a.state or "-",a.pid or "-",version,compat))
  end
  for _,d in ipairs(state.deployments or {}) do
    print(("  [deploying] %-16s %s/%s files  %s/%s bytes"):format(
      d.app or "-",d.files or 0,d.expected_files or 0,d.bytes or 0,d.expected_bytes or 0
    ))
  end
end

local function print_app(app)
  if type(app)~="table" then return end
  print("App: "..tostring(app.name or "-"))
  print("State: "..tostring(app.state or "-").."  PID: "..tostring(app.pid or "-"))
  print("Version: "..tostring(app.version or "-"))
  print("Entrypoint: "..tostring(app.entrypoint or "app.lua"))
  print("Description: "..tostring(app.description or "-"))
  print("Roles: "..table.concat(app.roles or {},", "))
  print("Requires: "..(#(app.requires or {})>0 and table.concat(app.requires,", ") or "(none)"))
  print("Compatible: "..tostring(app.compatible~=false))
  if #(app.missing_capabilities or {})>0 then
    print("Missing: "..table.concat(app.missing_capabilities,", "))
  end
end

local function safe_app(name)
  if type(name)~="string" or name=="" or name=="." or name==".." then return nil end
  if not name:match("^[%w][%w%._%-]*$") then return nil end
  return name
end

local function collect_files(base)
  base=host(base)
  if not fs.exists(base) or not fs.isDir(base) then return nil,"source directory not found: "..base end
  local out={}
  local function walk(dir,rel)
    for _,name in ipairs(fs.list(dir)) do
      local full=fs.combine(dir,name)
      local nextRel=rel=="" and name or (rel.."/"..name)
      if fs.isDir(full) then
        walk(full,nextRel)
      else
        out[#out+1]={path=nextRel,full=full,size=fs.getSize(full)}
      end
    end
  end
  walk(base,"")
  table.sort(out,function(a,b)return a.path<b.path end)
  return out
end

local function total_bytes(files)
  local n=0
  for _,f in ipairs(files or {}) do n=n+(f.size or 0) end
  return n
end

local function rpc(target,msg,timeout)
  local sent=rednet.send(target,msg,protocol)
  if not sent then return nil,"unable to send to app server ID "..tostring(target) end
  local deadline=(os.epoch and os.epoch("utc") or 0)+math.floor((timeout or 4)*1000)
  while true do
    local now=os.epoch and os.epoch("utc") or 0
    local remaining=math.max(0,(deadline-now)/1000)
    if remaining<=0 then return nil,"app server timed out" end
    local sender,res=rednet.receive(protocol,remaining)
    if not sender then return nil,"app server timed out" end
    if sender==target and type(res)=="table" then
      if not res.ok then return nil,res.error or "remote command failed" end
      return res
    end
  end
end

local function deploy(target,app,source,autostart)
  app=safe_app(app)
  if not app then return nil,"invalid app name" end
  source=source or ("/srv/cclua/deploy/"..app)

  local files,err=collect_files(source)
  if not files then return nil,err end
  if #files==0 then return nil,"source directory is empty" end

  local manifest=nil
  local manifestPath=host(source.."/app.json")
  if fs.exists(manifestPath) and not fs.isDir(manifestPath) then
    local h=fs.open(manifestPath,"r")
    local raw=h and h.readAll() or nil
    if h then h.close() end
    local ok,data=pcall(textutils.unserializeJSON,raw or "")
    if not ok or type(data)~="table" then return nil,"invalid app.json manifest" end
    manifest=data
    if manifest.name and tostring(manifest.name)~=app then
      return nil,"app.json name does not match deployment name"
    end
  end

  local entry=tostring(manifest and manifest.entrypoint or "app.lua"):gsub("\\","/")
  if entry:sub(1,1)=="/" or entry:find("..",1,true) then
    return nil,"invalid manifest entrypoint"
  end
  local hasEntry=false
  for _,f in ipairs(files) do if f.path==entry then hasEntry=true;break end end
  if not hasEntry then return nil,"source is missing entrypoint "..entry end

  local bytes=total_bytes(files)
  local version=tostring(manifest and manifest.version or (os.epoch and os.epoch("utc") or 0))

  local begin,begErr=rpc(target,{
    protocol=protocol,op="deploy_begin",app=app,
    files=#files,bytes=bytes,version=version,autostart=autostart==true
  },5)
  if not begin then return nil,begErr end

  print(("Deploying %s: %d files, %d bytes"):format(app,#files,bytes))
  local sentBytes=0

  for index,f in ipairs(files) do
    local ok,startErr=rpc(target,{
      protocol=protocol,op="deploy_file_begin",app=app,path=f.path,size=f.size
    },5)
    if not ok then
      rpc(target,{protocol=protocol,op="deploy_abort",app=app,reason=startErr},2)
      return nil,startErr
    end

    local h,openErr=fs.open(f.full,"r")
    if not h then
      rpc(target,{protocol=protocol,op="deploy_abort",app=app,reason=openErr},2)
      return nil,openErr or ("cannot open "..f.path)
    end

    while true do
      local chunk=h.read(4096)
      if not chunk then break end
      local ack,chunkErr=rpc(target,{
        protocol=protocol,op="deploy_chunk",app=app,path=f.path,data=chunk
      },5)
      if not ack then
        h.close()
        rpc(target,{protocol=protocol,op="deploy_abort",app=app,reason=chunkErr},2)
        return nil,chunkErr
      end
      sentBytes=sentBytes+#chunk
    end
    h.close()

    local ended,endErr=rpc(target,{
      protocol=protocol,op="deploy_file_end",app=app,path=f.path
    },5)
    if not ended then
      rpc(target,{protocol=protocol,op="deploy_abort",app=app,reason=endErr},2)
      return nil,endErr
    end

    local pct=bytes>0 and math.floor((sentBytes/bytes)*100) or 100
    print(("  [%d/%d] %-28s %d%%"):format(index,#files,f.path,pct))
  end

  local committed,commitErr=rpc(target,{
    protocol=protocol,op="deploy_commit",app=app
  },8)
  if not committed then return nil,commitErr end

  print(("Deployment complete: %s version %s"):format(app,version))
  print_state(committed.state)
  return true
end

return {main=function(ctx,args)
  local machine=config.machine()
  local target=tonumber(machine.app_server_id) or 2
  local cmd=args[1] or "status"

  net.open_management_modems()

  if cmd=="deploy" then
    if not args[2] then usage();return 1 end
    local source=nil
    local autostart=false
    for i=3,#args do
      if args[i]=="--start" then autostart=true
      elseif not source then source=args[i] end
    end
    local ok,err=deploy(target,args[2],source,autostart)
    if not ok then print("Deploy failed: "..tostring(err));return 1 end
    return 0
  end

  local msg={protocol=protocol,op=cmd}

  if cmd=="start" or cmd=="stop" or cmd=="restart"
    or cmd=="rollback" or cmd=="remove" or cmd=="info" then
    if not args[2] then usage();return 1 end
    msg.app=args[2]
  elseif cmd~="status" and cmd~="list" then
    usage();return 1
  end

  local res,err=rpc(target,msg,5)
  if not res then print("Command failed: "..tostring(err));return 1 end
  if cmd=="info" then print_app(res.app) else print_state(res.state) end
  return 0
end}
