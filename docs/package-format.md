# CCLUA Package Format (.luapkg)

## Purpose

`.luapkg` is the installable package format for CCLUA-LINUX.

It should feel Ubuntu-like to users while remaining native to CC:Tweaked and Lua.

## Logical package layout

```text
package/
├─ manifest.json
├─ payload/
│  ├─ usr/
│  ├─ etc/
│  ├─ var-template/
│  └─ opt/
├─ scripts/
│  ├─ preinstall.lua
│  ├─ postinstall.lua
│  ├─ preremove.lua
│  └─ postremove.lua
└─ signature.json
```

## Manifest fields

```json
{
  "format": "cclua-luapkg",
  "format_version": 1,
  "name": "coreutils",
  "version": "0.1.0",
  "architecture": "cclua",
  "description": "Ubuntu-compatible core utilities for CCLUA",
  "depends": [],
  "recommends": [],
  "conflicts": [],
  "provides": [],
  "commands": [],
  "services": [],
  "files": [],
  "source": {
    "ubuntu_package": "coreutils",
    "ubuntu_reference": "22.04.5"
  }
}
```

## Package database

Installed state should track:

- package/version
- installed files
- package dependencies
- installed time
- source channel/repository
- conformance status
- configuration ownership
- package state: installed, unpacked, broken, removed

## Repository model

The manager may mirror/copy package metadata from GitHub and serve packages to nodes.

Suggested channels:

- stable
- beta
- development

## Configuration preservation

Package upgrades must distinguish between:

- vendor/default config
- locally modified config
- generated machine state

Never silently overwrite local config when an upgrade changes the default.

## Script safety

Lifecycle scripts execute in a restricted package context rather than unrestricted kernel context.

Allowed capabilities should be explicitly declared by package metadata.

## CLI target

User-facing package commands should eventually support familiar operations:

```text
apt update
apt install <pkg>
apt remove <pkg>
apt upgrade
apt search <query>
apt show <pkg>
dpkg -l
dpkg -S <path>
```

The implementation is CCLUA-native; compatibility is behavioral, not binary.
