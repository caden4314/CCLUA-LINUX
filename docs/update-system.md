# CCLUA Update System

## Flow

```text
GitHub
  |
  v
Manager GitHub bridge
  |
  +-- manifest cache
  +-- package cache
  +-- image cache
  |
  v
Nodes
```

## Principle

The manager is the update authority for the cluster.

Ordinary nodes do not need GitHub credentials.

## Release manifest

A release manifest contains:

- channel
- image role
- version
- build ID
- required boot/runtime version
- image SHA256
- package repository snapshot
- minimum manager protocol
- release notes metadata
- signature

## Node update state machine

```text
IDLE
 -> CHECKING
 -> DOWNLOADING
 -> VERIFYING
 -> STAGING
 -> READY
 -> ACTIVATING
 -> HEALTH_CHECK
 -> COMMITTED

failure:
 -> ROLLBACK
 -> DEGRADED
```

## A/B system slots

Nodes always stage a system image into the inactive slot.

Example:

- currently active: SystemA
- download/stage: SystemB
- next boot: pending SystemB
- health pass: SystemB becomes known-good
- health fail: return to SystemA

## Health gates

Before commit:

- image integrity verified
- boot completed
- kernel runtime responsive
- required services healthy
- local storage writable
- network healthy when required by role

## Manager dashboard

Manager should expose:

- current version per node
- available version
- update channel
- download/stage progress
- pending reboot/activation
- rollback state
- last failure reason

## GitHub repository channels

Initially channels can map to Git refs/releases:

- development -> main/latest development build
- beta -> prerelease
- stable -> signed release

## Offline behavior

Nodes continue running their currently committed slot if the manager or GitHub is unavailable.

A failed update must never invalidate the last known-good system.
