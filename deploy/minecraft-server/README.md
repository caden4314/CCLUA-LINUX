# CCLUA Minecraft Server Deployment

Production-capable copied-world server on NEWMAIN.

## Endpoint

- MagicDNS: `desktop-1r77lod.tail4ae277.ts.net:25565`
- Tailscale IPv4: `100.76.188.26:25565`
- Server root: `E:\Minecraft\CCLUA-Server`

The server binds only to NEWMAIN's Tailscale IPv4 address.

## Runtime

`Start-CCLUAServer.ps1` starts Fabric 1.20.1 with:

- Temurin Java 17
- Fabric Loader 0.19.5
- 4 GB initial heap
- 10 GB maximum heap
- G1GC
- crash-loop protection
The supervisor exits after a normal Minecraft shutdown and only restarts unexpected
non-zero exits. More than three crashes within ten minutes trips loop protection.

## Controls

Clean stop:

```powershell
E:\Minecraft\CCLUA-Server\Stop-CCLUAServer.ps1
```

Clean backup and restart:

```powershell
E:\Minecraft\CCLUA-Server\Request-Backup.ps1
```

The backup path is `E:\Minecraft\CCLUA-Server\backups`; the newest ten are retained.

## Auto-start and backups

NEWMAIN's current user has an HKCU Run entry named `CCLUAMinecraftServer`.
Task Scheduler job `CCLUA Minecraft Backup` requests a clean backup/restart daily at 04:00.
## Client

The managed client pack is described by `docs/minecraft-client-pack.json`.
The full client manifest is `docs/pack-client-full.json`.

CYBER-PC is `desktop-6hid6ll` / `100.75.135.122`.
A matching Prism import ZIP was sent to it with Tailscale Taildrop.

## Rollback

The original singleplayer `COMPUTERS2` save remains outside the dedicated server root.
A pre-dedicated snapshot is stored under `E:\Minecraft\CCLUA-Backups`.
