local M={}
function M.resolve(name)
 if not name or name=="" then return nil end
 if name:sub(1,1)=="/" then return name end
 local candidates={
  "/usr/bin/"..name..".lua",
  "/usr/sbin/"..name..".lua",
  "/bin/"..name..".lua",
  "/sbin/"..name..".lua"
 }
 for _,p in ipairs(candidates)do if fs.exists(p:gsub("^/","")) then return p end end
 return nil
end
function M.load(path)
 if not path then return nil,"ENOENT" end
 local host=path:gsub("^/","")
 if not fs.exists(host) then return nil,"ENOENT" end
 local ok,mod=pcall(dofile,host)
 if not ok then return nil,mod end
 if type(mod)=="function" then return {main=mod} end
 if type(mod)=="table" and type(mod.main)=="function" then return mod end
 return nil,"ENOEXEC"
end
return M
