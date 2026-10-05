# CCLUA Minecraft Dedicated Server / Modpack Plan

## Goal

Move COMPUTERS2 from Minecraft's integrated server to a dedicated Fabric 1.20.1 server hosted on NEWMAIN while preserving the current world, CCLUA fleet, theater, Create/building content, and ComputerCraft state.

The server should do as much simulation, generation, storage, networking, and LOD generation as practical so weaker clients primarily render and handle UI/input.

## Current host baseline

- CPU: AMD Ryzen 7 5800X, 8 cores / 16 threads
- RAM: 32 GB
- GPU: GeForce RTX 5070 Ti
- Minecraft: 1.20.1 Fabric
- CC:Tweaked: 1.120.2
- CCLUA CCPerf: 0.3.5 development line
- World: COMPUTERS2

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
