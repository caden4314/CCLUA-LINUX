return {main=function(ctx,args) local rc=0;for _,n in ipairs(args)do local p=ctx.kernel.exec.resolve(n);if p then print(p)else rc=1 end end;return rc end}
