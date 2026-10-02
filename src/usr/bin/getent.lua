return {main=function(ctx,args)
 local db=args[1];local key=args[2]
 if db=="passwd" then
  local users=ctx.kernel.users.all()
  if key then
   local u=users[key] or ctx.kernel.users.by_uid(tonumber(key))
   if not u then return 2 end
   print(("%s:x:%d:%d:%s:%s:%s"):format(u.name,u.uid,u.gid,u.gecos or "",u.home,u.shell))
  else
   local arr={}for _,u in pairs(users)do arr[#arr+1]=u end;table.sort(arr,function(a,b)return a.uid<b.uid end)
   for _,u in ipairs(arr)do print(("%s:x:%d:%d:%s:%s:%s"):format(u.name,u.uid,u.gid,u.gecos or "",u.home,u.shell))end
  end
  return 0
 elseif db=="group" then
  local groups=ctx.kernel.users.load_groups()
  local function show(g)print(("%s:x:%d:%s"):format(g.name,g.gid,table.concat(g.members or {},",")))end
  if key then local g=groups[key];if not g then for _,x in pairs(groups)do if x.gid==tonumber(key) then g=x break end end end;if not g then return 2 end;show(g)
  else local arr={}for _,g in pairs(groups)do arr[#arr+1]=g end;table.sort(arr,function(a,b)return a.gid<b.gid end);for _,g in ipairs(arr)do show(g)end end
  return 0
 end
 print("getent: supported databases: passwd group");return 2
end}
