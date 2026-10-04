local compositor=dofile("/usr/lib/cclua/desktop/compositor.lua")
return {
  main=function(ctx,args)
    return compositor.run(ctx,args)
  end
}
