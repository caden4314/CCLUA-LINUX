# Ubuntu 22.04 Compatibility Targets

Compatibility means matching useful command/service behavior and data conventions where practical. It does not mean Linux binary compatibility.

## Tier 0 — Foundation

Required before applications:

- boot/init
- VFS
- processes/PIDs
- signals
- services
- users/groups
- permissions
- PTYs/terminal
- time
- networking
- DNS/service discovery
- package database
- logging/journal
- /proc, /dev, /sys providers

## Tier 1 — Core shell utilities

Priority commands:

- sh
- bash-compatible CCLUA shell subset
- ls
- cp
- mv
- rm
- mkdir
- rmdir
- cat
- echo
- printf
- pwd
- cd (shell builtin)
- touch
- head
- tail
- wc
- sort
- grep
- find
- which
- env
- true
- false
- sleep
- date
- uname
- hostname
- whoami
- id
- clear

## Tier 2 — System administration

- ps
- top
- kill
- killall
- free
- df
- mount
- umount
- uptime
- dmesg
- systemctl
- journalctl
- hostnamectl
- useradd
- userdel
- passwd
- groups

## Tier 3 — Networking

- ip
- ping
- hostname
- ss
- curl-like HTTP client
- wget-like downloader
- ssh
- scp
- DNS lookup tool

## Tier 4 — Packages/updates

- apt
- apt-cache behavior subset
- dpkg query subset
- repo/update commands
- manager package mirror

## Tier 5 — Server programs

Planned native Lua services:

- SSH server
- HTTP server
- static file server
- package repository
- DNS/service discovery
- syslog/journal receiver
- scheduler/cron-like service
- cluster agent

## Tier 6 — Desktop

Desktop image adds:

- compositor
- window manager
- desktop shell
- terminal
- file manager
- settings
- text editor
- process/system monitor
- package/update UI
- network UI

## Conformance philosophy

For each compatible program, track:

- supported arguments/options
- exit codes
- stdout/stderr shape
- file/config behavior
- documented deviations
- Ubuntu 22.04 reference package/version
