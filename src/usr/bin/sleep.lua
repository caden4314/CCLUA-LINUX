return {main=function(ctx,args) local n=tonumber(args[1] or "1") or 1;ctx.kernel.runtime.sleep(n);return 0 end}
