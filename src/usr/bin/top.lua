return {main=function(ctx,args)
  term.clear();term.setCursorPos(1,1)
  term.setTextColor(colors.cyan);print("top - CCLUA Ubuntu Server")
  term.setTextColor(colors.white)
  print(("Tasks: %d total"):format(#ctx.kernel.process.all()))
  print("PID USER       STATE      COMMAND")
  for _,p in ipairs(ctx.kernel.process.all())do
    local u=ctx.kernel.users.by_uid(p.uid)
    local name=(u and u.name) or tostring(p.uid)
    print(("%3d %-10s %-10s %s"):format(p.pid,name,p.state,p.name))
  end
  return 0
end}
