local M={}; local users={root={uid=0,gid=0,name="root",home="/root",shell="/usr/bin/bash.lua"},caden={uid=1000,gid=1000,name="caden",home="/home/caden",shell="/usr/bin/bash.lua"}}
function M.by_name(n)return users[n]end
function M.by_uid(uid)for _,u in pairs(users)do if u.uid==uid then return u end end end
function M.all()return users end
return M
