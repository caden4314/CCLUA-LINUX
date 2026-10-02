local M={}
function M.send(t,m)t.mailbox[#t.mailbox+1]=m;return true end
function M.recv(p)if #p.mailbox==0 then return nil end return table.remove(p.mailbox,1)end
function M.pipe()
 local st={queue={},closed=false}; local r={}; local w={}
 function r.read()if #st.queue==0 then return nil end return table.remove(st.queue,1)end
 function w.write(v)if st.closed then return nil,"EPIPE" end st.queue[#st.queue+1]=v;return true end
 function w.close()st.closed=true end
 return r,w
end
return M
