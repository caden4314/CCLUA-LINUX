# CCLUA-LINUX

CCLUA-LINUX is a Linux-inspired operating environment for CC:Tweaked, implemented in Lua.

The system boots from an encoded, immutable `.luaiso` image through a small stage-0 Lua bootstrap, then runs a custom kernel/runtime, service manager, VFS, networking stack, compositor, desktop, package system, diagnostics, and secure remote-shell subsystem.

## Boot path

```
CraftOS / CC:Tweaked
  -> startup.lua / bootstrap.lua
  -> decode + verify CCLUA-LINUX.luaiso
  -> immutable in-memory /System
  -> kernel + scheduler
  -> process/session manager
  -> services + drivers
  -> compositor + desktop
  -> user applications
```

## Storage model

- `/System` — immutable files loaded from the `.luaiso`
- `/Users/<user>` — persistent writable user data
- `/home/<user>` — alias of the user's persistent data
- `/AppData` — persistent application state
- `/Temp` — writable temporary state
Machine identity, private keys, diagnostics state, application data, and user files are never stored in the immutable system image.

## Runtime architecture

The current runtime includes:

- cooperative kernel scheduler with PIDs and task isolation
- process/session manager with user, session, kind, capabilities, and PTY metadata
- capability-scoped VFS views for userspace processes
- desktop applications running as scheduled processes
- dependency-aware service startup
- bounded service restart policy with exponential backoff
- CCLUA NET networking
- package installation and command execution
- lua-ssh with per-session scheduled shell processes
- diagnostic telemetry that excludes user documents, secrets, and shell content

## Building

From PowerShell on the development machine:

```powershell
cd C:\Dev\CCLUA-LINUX
.\Build.ps1
```

The build produces `dist\CCLUA-LINUX.luaiso` and prepares the local CraftOS-PC runtime.

## Regression test
```powershell
.\Test.ps1
```

The smoke test creates disposable CraftOS-PC computer ID `2799`, boots the generated image, and verifies the scheduler, process/PTY layer, capability enforcement, service dependencies, package guards, VFS storage contract, and core daemons.

A successful run reports `CCLUA_LINUX_SMOKE_PASS`.

## Development status

Current development version: **0.1.0 / Glassforge**

The project is still under active development. Interfaces, image format details, package ABI, networking behavior, and security boundaries may change before a stable release.

## Local tooling

CraftOS-PC binaries are intentionally excluded from Git. Place a compatible CraftOS-PC installation under:

`tools\CraftOS-PC\`

before using the local launcher or regression test.
