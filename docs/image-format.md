# CCLUA .luaiso Image Format

## Purpose

A `.luaiso` is the immutable system image consumed by the CCLUA bootloader.

Supported roles:

- `ubuntu-22.04-server`
- `ubuntu-22.04-desktop`
- `manager`

All roles share the same kernel/runtime ABI.

## Container goals

- deterministic builds
- compact enough for CC:Tweaked storage
- integrity-verifiable before boot
- immutable system payload
- explicit metadata/version/role
- support A/B system slots
- no machine secrets inside the image

## Logical layout

```text
CCLUA-IMAGE/
├─ manifest.json
├─ signature.json
├─ system/
│  ├─ boot/
│  ├─ kernel/
│  ├─ lib/
│  ├─ bin/
│  ├─ sbin/
│  ├─ etc/
│  ├─ usr/
│  └─ var-template/
└─ packages/
```

The packed `.luaiso` representation may use compression/encoding, but the logical paths above remain stable.

## Manifest

Minimum manifest fields:

```json
{
  "format": "cclua-luaiso",
  "format_version": 1,
  "name": "CCLUA Ubuntu 22.04 Server",
  "role": "ubuntu-22.04-server",
  "version": "0.1.0",
  "channel": "development",
  "ubuntu_reference": "22.04.5",
  "architecture": "cclua",
  "build_id": "unique-build-id",
  "created_utc": "ISO-8601",
  "entrypoint": "/system/boot/init.lua",
  "required_runtime": 1,
  "payload_sha256": "...",
  "files": []
}
```

Each file record should eventually contain:

- path
- size
- SHA256
- mode/attributes
- package owner
- source/provenance tag

## Writable state

Images must never contain machine-unique writable state.

Persistent state belongs outside the image:

```text
/SystemA
/SystemB
/Users
/home
/AppData
/var
/Temp
/Boot
```

`/System` is a virtual mount pointing at the active A/B system slot.

## A/B activation

Boot metadata tracks:

- active slot
- pending slot
- previous known-good slot
- boot attempt counter
- health deadline
- rollback reason

A newly staged slot is marked pending. It becomes known-good only after:

1. kernel/runtime initialization succeeds,
2. required services reach healthy state,
3. network stack initializes when required for the role,
4. the boot-health marker is committed.

Failure automatically selects the previous known-good slot.

## Integrity

At minimum:

- SHA256 over every file
- SHA256 over canonical manifest/payload
- optional public-key signature over manifest digest

Machine secrets and private signing keys must never be stored in the image.
