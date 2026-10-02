return {main=function(ctx,args)
 local name=args[1];local action=args[2] or "status"
 if not name then print("Usage: service <service> <start|stop|restart|status>");return 1 end
 if action=="status" then
  local u=ctx.kernel.services:get(name)
  if not u then print(name..": unrecognized service");return 4 end
  print(("%s is %s"):format(u.name,u.state));return u.state=="active" and 0 or 3
 elseif action=="start" then local ok,e=ctx.kernel.services:start(name);if not ok then print(e);return 1 end;return 0
 elseif action=="stop" then local ok,e=ctx.kernel.services:stop(name);if not ok then print(e);return 1 end;return 0
 elseif action=="restart" then local ok,e=ctx.kernel.services:restart(name);if not ok then print(e);return 1 end;return 0
 end
 print("service: unsupported action "..action);return 1
end}
