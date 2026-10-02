local M={};local mounts={}
local function norm(path)
 path=tostring(path or "/"):gsub("\\","/")
 if path:sub(1,1)~="/" then path="/"..path end
 local parts={}
 for p in path:gmatch("[^/]+")do
  if p==".." then table.remove(parts)
  elseif p~="." and p~="" then parts[#parts+1]=p end
 end
 return "/"..table.concat(parts,"/")
end
function M.normalize(p)return norm(p)end
function M.mount(p,prov)mounts[norm(p)]=prov;return true end
function M.mounts()return mounts end
local function resolve(path)
 local p=norm(path);local best=nil;local prov=nil
 for m,x in pairs(mounts)do
  if m=="/" or p==m or p:sub(1,#m+1)==m.."/" then
   if not best or #m>#best then best=m;prov=x end
  end
 end
 if not prov then return nil,"ENOENT" end
 local sub=(best=="/") and p or p:sub(#best+1)
 if sub=="" then sub="/" end
 return prov,sub
end
function M.call(op,path,...)
 local p,sub=resolve(path)
 if not p then return nil,sub end
 local f=p[op]
 if not f then return nil,"ENOSYS" end
 return f(sub,...)
end
for _,op in ipairs({"exists","isDir","list","open","delete","mkdir","move","copy","stat"})do
 M[op]=function(path,...)return M.call(op,path,...)end
end
return M
