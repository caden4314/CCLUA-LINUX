local M={}
function M.raise(k,msg,details)
 k.log.write("emerg","panic",msg,details)
 term.setBackgroundColor(colors.black);term.setTextColor(colors.red);term.clear();term.setCursorPos(1,1)
 print("CCLUA KERNEL PANIC");term.setTextColor(colors.white);print(tostring(msg))
 error("KERNEL PANIC: "..tostring(msg),0)
end
return M
