# CCLUA Ubuntu-Compatible Filesystem Contract

## Goals

- familiar Ubuntu 22.04 layout
- CC:Tweaked-safe semantics
- clean separation of immutable system data and writable machine/user data
- pseudo-filesystems implemented by Lua providers

## Top-level namespace

```text
/
├─ bin -> /usr/bin
├─ sbin -> /usr/sbin
├─ boot
├─ dev
├─ etc
├─ home
├─ lib -> /usr/lib
├─ mnt
├─ opt
├─ proc
├─ root
├─ run
├─ srv
├─ sys
├─ tmp
├─ usr
└─ var
```

## Immutable system paths

Backed by the active `.luaiso`:

- /usr/bin
- /usr/sbin
- /usr/lib
- /usr/share
- system defaults under /etc when not overridden

## Writable paths

Persist independently of the system image:

- /etc overrides
- /home
- /root
- /var
- /opt
- /srv
- /AppData-equivalent backing storage

## Pseudo filesystems

### /proc

Generated dynamically.

Initial targets:

- /proc/uptime
- /proc/meminfo
- /proc/cpuinfo
- /proc/version
- /proc/<pid>/
- /proc/net/

### /dev

Virtual device/peripheral namespace.

Examples:

- /dev/null
- /dev/zero
- /dev/random
- /dev/tty
- /dev/console
- peripheral-backed devices

### /sys

CCLUA device/service/runtime metadata.

## Permissions

Initial model:

- UID/GID
- owner/group/other rwx bits
- root UID 0
- user home ownership
- process effective UID/GID
- optional capability extensions

CC:Tweaked host filesystem permissions are not authoritative; permissions are enforced by the CCLUA VFS.

## Links

Symbolic links are virtual metadata managed by the VFS.

## Mounts

Mount table supports:

- image filesystem
- persistent filesystem
- pseudo filesystems
- removable/peripheral storage
- network mounts later

## Path compatibility

The shell and APIs normalize:

- .
- ..
- absolute paths
- relative paths
- symlink traversal
- home expansion handled by the shell

The VFS must reject attempts to escape mounted roots through malformed paths.
