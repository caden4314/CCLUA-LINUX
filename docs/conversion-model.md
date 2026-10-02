# Ubuntu -> CCLUA conversion model

The converter does not attempt binary translation of Ubuntu into ComputerCraft. It extracts semantics and source data from the real Ubuntu image and builds a CC:Tweaked-native implementation.

## A. Reusable / transformable content

Examples:

- `/etc/os-release`
- `/etc/passwd`, `/etc/group` schemas
- hostname/hosts/resolver structure
- MIME/type databases where practical
- package names, dependency metadata and descriptions
- desktop metadata
- service names and default enablement
- static configuration files which do not depend on Linux-specific binary formats

All imported content must retain provenance metadata.

## B. Behavioral reference

These are parsed and indexed but normally not copied verbatim into the CCLUA runtime:

- systemd unit files
- init/service scripts
- shell scripts
- package maintainer scripts
- command-line help/manpage semantics
- default configs
- network/service relationships
- package dependency graphs

We use these to write equivalent Lua programs and libraries.

## C. Native CCLUA replacements

Must be implemented for CC:Tweaked:

- kernel/process scheduler
- VFS and pseudo-filesystems
- process IDs, signals and IPC
- service manager
- terminal/PTY model
- virtual networking/IP/ports/DNS
- user/group/permission model
- package manager
- update system
- Ubuntu-compatible command implementations
- server daemons
- graphical compositor/window manager
- desktop shell and applications
- hardware/peripheral abstraction

## Conversion database

Every discovered path should eventually produce an inventory entry containing:

- source image
- source path
- object type
- package owner when known
- classification
- replacement module/program
- implementation state
- notes
- source hash

This gives us measurable conversion coverage instead of a hand-written approximation.
