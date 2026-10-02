return function(ctx)
 while true do
  coroutine.yield("wait_event","cclua_journal_tick")
 end
end
