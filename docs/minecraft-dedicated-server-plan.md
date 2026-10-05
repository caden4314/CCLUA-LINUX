# CCLUA Minecraft Dedicated Server / Modpack Plan

## Goal

Move COMPUTERS2 from Minecraft's integrated server to a dedicated Fabric 1.20.1 server hosted on NEWMAIN while preserving the current world, CCLUA fleet, theater, Create/building content, and ComputerCraft state.

The server should do as much simulation, generation, storage, networking, and LOD generation as practical so weaker clients primarily render and handle UI/input.

## Deployment status — 2026-10-05

The first production-capable copied-world deployment is complete on NEWMAIN:

- server root: `E:\Minecraft\CCLUA-Server`
- source singleplayer world remains untouched after the clean migration snapshot
- rollback archive: `E:\Minecraft\CCLUA-Backups\COMPUTERS2-pre-dedicated-20261005-143537.zip`
- Minecraft 1.20.1 / Fabric Loader 0.19.5 / Java 17
- exact server pack: 48 jars
- exact full client pack: 59 jars
- Tailscale listener: `100.76.188.26:25565`
- MagicDNS endpoint: `desktop-1r77lod.tail4ae277.ts.net:25565`
- manager ID 0: CURRENT
- copied CCLUA fleet: 20/20 CURRENT, 20/20 POST PASSED, 20/20 HEALTHY
- theater: 223x73 main display, 55/55 relays, 22/22 speakers, bridge ONLINE
- supervisor: clean-stop controls, crash restart with loop protection, logon auto-start
- backup policy: daily 04:00 clean stop -> archive -> restart, newest 10 retained
- client pack was Taildropped to CYBER-PC (`desktop-6hid6ll`)

Known non-fatal startup warnings remain around legacy datapack recipes and Wired Redstone's
Create integration API. The server reaches `Done`, stays running, and the CCLUA fleet remains healthy.

## Current host baseline

- CPU: AMD Ryzen 7 5800X, 8 cores / 16 threads
- RAM: 32 GB
- GPU: GeForce RTX 5070 Ti
- Minecraft: 1.20.1 Fabric
- CC:Tweaked: 1.120.2
- CCLUA CCPerf: 0.3.6, including dedicated-server HQ PCM transport
- Java: Eclipse Temurin OpenJDK 17.0.20.1
- World: COMPUTERS2
- Tailscale: 1.102.4, backend running
- Tailnet IPv4: 100.76.188.26
- Tailnet IPv6: fd7a:115c:a1e0::6831:bc1b
- MagicDNS: desktop-1r77lod.tail4ae277.ts.net

This hardware is suitable for the first dedicated-server phase without waiting for the planned AM5 upgrade.

## What the server can offload

The dedicated server should own world ticks, entity/AI simulation, redstone, Create simulation, ComputerCraft execution, chunk loading/generation, world saves, network authority, server-side mod logic, and scheduled CCLUA workloads.

Chunk pregeneration and Distant Horizons server-side LOD generation can also be performed on NEWMAIN. Weak clients can then receive already-generated world/LOD data instead of generating it locally.

The server cannot replace the client's GPU rasterizer. Final terrain/entity rendering, shaders, GUI drawing, and frame presentation still happen on each client.
## Pack architecture

Maintain four explicit mod layers instead of copying the current mods folder blindly.

### common

Required on both server and clients when the mod changes registries, blocks/items, networking, or gameplay state.

Initial common candidates include Fabric API, CC:Tweaked, CCLUA CCPerf, Create Fabric, Create Connected, Create Deco, Adorn, Another Furniture, Chipped, Chisel, Decorative Blocks, Handcrafted, Macaw's building mods, Rechiseled/Create integration, Roadworks, TrafficCraft, Wired Redstone, required libraries, and other world-content dependencies.

### server-only

Use this layer for simulation and server performance where compatibility tests pass:

- Lithium
- FerriteCore
- ServerCore
- Krypton
- C2ME, after an A/B world-copy test
- Chunky for pregeneration
- Distant Horizons server component / server-supported build for LOD generation
- monitoring, backup, and administration utilities

ModernFix should be evaluated by benchmark rather than enabled automatically.

### client-performance

Weak-client profile:
- Sodium
- Sodium Extra / Reese's Sodium Options
- ImmediatelyFast
- EntityCulling
- FerriteCore
- Lithium where client-supported
- Indium where required by the render stack
- Distant Horizons if server-generated LOD streaming is used
Use a low vanilla render distance and let server-side pregeneration plus DH provide long-distance context.

### client-visual / authoring

Keep optional heavy/editor features out of the weak-client baseline: Iris/shaders, Axiom, Litematica/Malilib, WorldEdit client tooling, dynamic lights, Continuity, EMI/Jade, and other authoring/QoL mods unless required for that user's role.

## Migration phases

### Phase 0 — compatibility gate

1. Make a clean save-and-exit backup of COMPUTERS2.
2. Export the exact active mod hashes and Fabric/Java versions.
3. Change CCPerf so HQ raw-PCM transport works in a dedicated SERVER environment while keeping the client decoder/sync barrier client-only.
4. Build a server-only copy and verify it boots with a copied world.
5. Do not point normal clients at it yet.

Acceptance: world loads with no missing registry entries, manager ID 0 and theater ID 23 boot, and no ComputerCraft IDs/files are lost.

### Phase 1 — dedicated LAN server

Create E:\Minecraft\CCLUA-Server\ with its own server.properties, mods, config, world, logs, backups, and startup scripts.

Start conservatively:
- simulation-distance: 6
- view-distance: 8
- dedicated Java 17 process
- heap target: 8–12 GB initially
- no shaders or client-only mods on the server
- automatic restart only after clean crash detection, never an unconditional kill loop

Bind on the LAN first. Keep the old singleplayer world untouched as rollback until several sessions pass.

### Phase 1B — private Tailscale transport

Production player access should move to Tailscale rather than public router port forwarding.

Current NEWMAIN tailnet identity:
- IPv4: `100.76.188.26`
- IPv6: `fd7a:115c:a1e0::6831:bc1b`
- MagicDNS: `desktop-1r77lod.tail4ae277.ts.net`

Server networking target:
- Java Edition TCP port `25565`
- no router/NAT port-forward for `25565`
- no Tailscale Funnel
- prefer `server-ip=100.76.188.26` once LAN-copy validation is complete so the production server binds only to the tailnet address
- clients use `desktop-1r77lod.tail4ae277.ts.net:25565` or the Tailscale IPv4 address
- keep the Minecraft query/RCON surfaces disabled unless a later management requirement specifically needs them

Windows Firewall should allow TCP/25565 only for the Tailscale address space and block an accidental public/LAN listener. Treat Tailscale ACL/grants as an additional authorization layer, not a replacement for the host firewall.

Planned production `server.properties` network values:

```properties
server-ip=100.76.188.26
server-port=25565
enable-query=false
enable-rcon=false
view-distance=8
simulation-distance=6
```

Planned Windows Firewall rule after the copied-world server is validated:

```powershell
New-NetFirewallRule -DisplayName "CCLUA Minecraft Tailscale" `
  -Direction Inbound -Action Allow -Protocol TCP `
  -LocalAddress 100.76.188.26 -LocalPort 25565 `
  -RemoteAddress 100.64.0.0/10
```

Verify the Java listener with `Get-NetTCPConnection -LocalPort 25565 -State Listen`; production should show the Tailscale IPv4 address rather than `0.0.0.0`.

Tailnet policy target:
- give the server a dedicated Minecraft service identity/tag when ready
- allow only approved players/groups to reach TCP/25565
- keep Caden Commander, SMB/NAS, RDP, and unrelated NEWMAIN services outside that player rule
- for players outside the main tailnet, prefer Tailscale machine sharing rather than exposing a public game port

Connection validation:
1. Verify the joining client resolves MagicDNS.
2. Run `tailscale ping` between client and NEWMAIN.
3. Prefer a direct peer-to-peer path for lowest latency.
4. DERP relay remains functional as fallback; investigate NAT/firewall behavior only if game latency is unacceptable.
5. Do not open UDP/41641 purely by habit; Tailscale normally needs no inbound firewall port. Consider it only when troubleshooting direct-connect performance.

### Phase 2 — precompute

Use Chunky to pregenerate the normal play/build area while no users are online. Generate Distant Horizons LOD data server-side if the chosen DH build supports the required server/client path.

This shifts expensive first-visit terrain generation away from weak clients and normal play sessions.

### Phase 3 — managed modpack

Generate versioned pack manifests:
- pack-common.json
- pack-server.json
- pack-client-performance.json
- pack-client-visual.json

Produce a Prism/Modrinth-compatible client pack so a weak machine receives the exact compatible common mods plus the light client profile. Keep server-only jars out of the client pack and client-only rendering/editor jars out of the server.

Version the pack alongside CCLUA/CCPerf releases and expose a small manifest/API endpoint so clients can see whether their pack is current before joining.

### Phase 4 — production service

Run the dedicated server under a Windows scheduled task or service wrapper with:
- clean shutdown command
- rotating world backups
- log rotation
- startup health check
- memory/TPS/MSPT/player/chunk metrics
- crash dump retention
- update staging rather than live replacement
- optional local web status page

Do not auto-update gameplay/content mods. Updates should be staged against a disposable world copy first.
## Performance target for weak clients

Server target: sustained 20 TPS with normal CCLUA fleet activity and acceptable MSPT during loaded Create/ComputerCraft areas.

Weak-client target: client can use 4–6 chunk vanilla render distance, low entity distance, no shaders, and server-generated/pregenerated world data while retaining useful long-distance LOD context.

A client's final FPS remains dependent on its GPU/CPU and the complexity of visible blocks/entities. The architecture minimizes client simulation/generation work but does not turn Java Edition into a video-streamed thin client.

## Validation checklist

- exact world seed/dimensions/player data preserved
- all CC computer IDs and files preserved
- manager/fleet network CURRENT and HEALTHY
- 55 theater relays and 22 theater speakers present
- CCPerf HQ PCM works across dedicated server -> client
- Create contraptions and building blocks survive migration
- no registry-remap warnings
- 20 TPS idle and under representative load
- weak-client joining tested with the performance pack
- rollback to the original singleplayer save remains possible
