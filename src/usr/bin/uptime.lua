return {main=function(ctx,args)
 local sec=math.floor(os.clock and os.clock() or 0)
 local d=math.floor(sec/86400);sec=sec%86400
 local h=math.floor(sec/3600);sec=sec%3600
 local m=math.floor(sec/60)
 print(("up %d days, %02d:%02d"):format(d,h,m))
 return 0
end}
