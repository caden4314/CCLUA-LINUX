local M={names={TERM=15,KILL=9,INT=2,HUP=1,STOP=19,CONT=18,CHLD=17},numbers={}}
for k,v in pairs(M.names) do M.numbers[v]=k end
function M.normalize(sig)
 if type(sig)=="number" then return M.numbers[sig] and sig or nil end
 sig=tostring(sig or ""):upper():gsub("^SIG","")
 return M.names[sig]
end
return M
