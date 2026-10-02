return {main=function(ctx,args)
 print("               Local time: "..(os.date and os.date("%Y-%m-%d %H:%M:%S") or tostring(os.epoch("utc"))))
 print("           Universal time: "..(os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or tostring(os.epoch("utc"))))
 print("                 RTC time: n/a")
 print("                Time zone: UTC (UTC, +0000)")
 print("System clock synchronized: yes")
 print("              NTP service: inactive")
 print("          RTC in local TZ: no")
 return 0
end}
