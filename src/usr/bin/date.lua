return {main=function(ctx,args) if os.date then print(os.date("%a %b %d %H:%M:%S %Y"))else print(tostring(os.epoch("utc")))end;return 0 end}
