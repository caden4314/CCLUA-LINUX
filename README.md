# CCLUA-LINUX

CCLUA-LINUX is a CC:Tweaked-native operating system project which uses real Ubuntu 22.04 LTS images as behavioral and filesystem references, then reimplements compatible userspace, services, commands, libraries, and desktop/server roles in Lua.

## Initial images

- Ubuntu 22.04.5 LTS Desktop AMD64
- Ubuntu 22.04.5 LTS Live Server AMD64

The original Ubuntu images are **inputs**, not runtime images. Native ELF binaries and the Linux kernel cannot execute directly under CC:Tweaked. The importer classifies image contents into:

1. **Reusable data** — configuration/data formats we can carry over or transform.
2. **Behavioral reference** — shell scripts, systemd units, defaults, package metadata, CLI behavior.
3. **CC-native replacement** — Linux kernel interfaces, ELF programs, daemons, GUI stack, device model, networking and process APIs which must be implemented in Lua.

## Planned roles

- `ubuntu-22.04-server`
- `ubuntu-22.04-desktop`
- `manager` for the four-computer cluster

## Repository status

Foundation/import pipeline in progress.
