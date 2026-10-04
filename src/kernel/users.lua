local M={}

local PASSWD="/etc/passwd"
local GROUP="/etc/group"

local function strip_bom(s)
  s=tostring(s or "")
  if s:sub(1,3)==string.char(0xEF,0xBB,0xBF) then return s:sub(4) end
  return s:gsub("^ï»¿","")
end

local function read_lines(path)
  local host=path:gsub("^/","")
  local out={}
  if not fs.exists(host) then return out end
  local h=fs.open(host,"r")
  if not h then return out end
  local first=true
  while true do
    local line=h.readLine()
    if not line then break end
    if first then line=strip_bom(line);first=false end
    out[#out+1]=line
  end
  h.close()
  return out
end

local function write_lines(path,lines)
  local host=path:gsub("^/","")
  local h=fs.open(host,"w")
  if not h then return nil,"cannot write "..path end
  for _,line in ipairs(lines) do h.writeLine(strip_bom(line)) end
  h.close()
  return true
end

function M.load_users()
  local out={}
  for _,line in ipairs(read_lines(PASSWD)) do
    if line~="" and line:sub(1,1)~="#" then
      local f={}
      for x in (line..":"):gmatch("(.-):") do f[#f+1]=x end
      if #f>=7 then
        out[f[1]]={
          name=f[1],password=f[2],uid=tonumber(f[3]) or -1,gid=tonumber(f[4]) or -1,
          gecos=f[5],home=f[6],shell=f[7]
        }
      end
    end
  end
  return out
end

function M.load_groups()
  local out={}
  for _,line in ipairs(read_lines(GROUP)) do
    if line~="" and line:sub(1,1)~="#" then
      local name,pw,gid,members=line:match("^([^:]*):([^:]*):([^:]*):(.*)$")
      if name then
        local m={}
        for x in tostring(members or ""):gmatch("[^,]+") do m[#m+1]=x end
        out[name]={name=name,password=pw,gid=tonumber(gid) or -1,members=m}
      end
    end
  end
  return out
end

function M.by_name(name) return M.load_users()[name] end
function M.by_uid(uid)
  for _,u in pairs(M.load_users()) do if u.uid==uid then return u end end
end
function M.all() return M.load_users() end

function M.groups_for(user)
  local u=type(user)=="table" and user or M.by_name(user)
  if not u then return {} end
  local out={}
  for name,g in pairs(M.load_groups()) do
    if g.gid==u.gid then out[#out+1]=g end
    for _,member in ipairs(g.members) do
      if member==u.name then out[#out+1]=g;break end
    end
  end
  table.sort(out,function(a,b)return a.gid<b.gid end)
  return out
end

function M.next_uid()
  local max=999
  for _,u in pairs(M.load_users()) do if u.uid>=1000 and u.uid>max then max=u.uid end end
  return max+1
end

function M.next_gid()
  local max=999
  for _,g in pairs(M.load_groups()) do if g.gid>=1000 and g.gid>max then max=g.gid end end
  return max+1
end

function M.add_group(name,gid)
  if M.load_groups()[name] then return nil,"group exists" end
  gid=gid or M.next_gid()
  local lines=read_lines(GROUP)
  lines[#lines+1]=("%s:x:%d:"):format(name,gid)
  local ok,e=write_lines(GROUP,lines)
  if not ok then return nil,e end
  return {name=name,gid=gid,members={}}
end

function M.delete_group(name)
  local groups=M.load_groups()
  if not groups[name] then return nil,"group not found" end
  local lines={}
  for _,line in ipairs(read_lines(GROUP)) do
    if line:match("^([^:]+):")~=name then lines[#lines+1]=line end
  end
  return write_lines(GROUP,lines)
end

function M.add_user(name,opts)
  opts=opts or {}
  if M.by_name(name) then return nil,"user exists" end

  local gid=opts.gid
  if not gid then
    local g=M.load_groups()[name] or M.add_group(name)
    if not g then return nil,"cannot create primary group" end
    gid=g.gid
  end

  local uid=opts.uid or M.next_uid()
  local home=opts.home or ("/home/"..name)
  local shell=opts.shell or "/usr/bin/bash.lua"
  local gecos=opts.gecos or ""

  local lines=read_lines(PASSWD)
  lines[#lines+1]=("%s:x:%d:%d:%s:%s:%s"):format(name,uid,gid,gecos,home,shell)
  local ok,e=write_lines(PASSWD,lines)
  if not ok then return nil,e end

  local host=home:gsub("^/","")
  if opts.create_home~=false and not fs.exists(host) then fs.makeDir(host) end
  return M.by_name(name)
end

function M.delete_user(name,remove_home)
  local u=M.by_name(name)
  if not u then return nil,"user not found" end
  if u.uid==0 then return nil,"cannot delete root" end

  local lines={}
  for _,line in ipairs(read_lines(PASSWD)) do
    if line:match("^([^:]+):")~=name then lines[#lines+1]=line end
  end
  local ok,e=write_lines(PASSWD,lines)
  if not ok then return nil,e end

  if remove_home then
    local host=u.home:gsub("^/","")
    if fs.exists(host) then fs.delete(host) end
  end
  return true
end

return M
