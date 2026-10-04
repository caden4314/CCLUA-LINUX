local config=dofile("/usr/lib/cclua/config.lua")

local function short(v)
  v=tostring(v or "-")
  return #v>12 and v:sub(1,12) or v
end

return {main=function(ctx,args)
  local machine=config.machine()
  if machine.role~="manager" and machine.role~="network-manager" then
    print("cclua-managerctl: this host is not a manager")
    return 1
  end

  local cmd=args[1] or "status"

  if cmd=="status" then
    local mgr=config.read_json("/var/lib/cclua/manager-state.json",{})
    local git=config.read_json("/var/lib/cclua/github/state.json",{})
    local d=mgr.delta or git.lastDelta or {}
    print("CCLUA Network Manager")
    print("---------------------")
    print(("State:       %s"):format(mgr.state or "STARTING"))
    print(("Repository:  %s [%s]"):format(mgr.repo or "caden4314/CCLUA-LINUX",mgr.ref or git.ref or "main"))
    print(("Installed:   %s"):format(short(mgr.installed_commit)))
    print(("Available:   %s"):format(short(mgr.image_commit or git.imageCommit or git.commit)))
    print(("Repo HEAD:   %s"):format(short(mgr.repo_commit or git.repoCommit)))
    print(("Active slot: %s"):format(mgr.active_slot or git.activeSlot or "-"))
    print(("Files:       %s"):format(mgr.files or git.files or "-"))
    print(("Delta:       +%d ~%d -%d =%d"):format(
      d.added or 0,d.changed or 0,d.removed or 0,d.unchanged or 0
    ))
    if mgr.current_action then
      print(("Working:     %s %s"):format(mgr.current_action,mgr.current_file or ""))
      print(("Progress:    %s/%s"):format(mgr.progress or 0,mgr.total or 0))
    end
    if mgr.last_error then print("Error:       "..tostring(mgr.last_error)) end
    return mgr.last_error and 1 or 0

  elseif cmd=="sync" then
    local force=args[2]=="--force" or args[2]=="-f"
    os.queueEvent("cclua_manager_sync",force)
    print("Manager sync requested"..(force and " (forced)" or ""))
    return 0

  elseif cmd=="nodes" then
    local peers=config.read_json("/var/lib/cclua/manager-peers.json",{nodes={}})
    print("ID   HOSTNAME                 ROLE             STATE")
    for _,n in ipairs(peers.nodes or {}) do
      local st=n.status or {}
      print(("%-4s %-24s %-16s %s"):format(
        tostring(n.id or "-"),
        tostring(n.hostname or "-"):sub(1,24),
        tostring(n.role or st.role or "-"):sub(1,16),
        tostring(st.system_state or "-")
      ))
    end
    if #(peers.nodes or {})==0 then print("(no enrolled/seen nodes)") end
    return 0
  end

  print("Usage: cclua-managerctl [status|sync [--force]|nodes]")
  return 1
end}
