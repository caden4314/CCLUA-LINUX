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


## Incremental manager synchronization

The manager keeps a manifest of repository-relative source paths and Git blob SHAs for the active A/B cache slot.

For each new Git commit it:

1. Fetches the repository tree metadata.
2. Compares the new `src/` blob SHAs with the active-slot manifest.
3. Copies the last-known-good slot locally into the inactive slot.
4. Removes paths deleted upstream.
5. Downloads only new or changed files.
6. Writes a new manifest and commit marker.
7. Flips the active slot only after staging succeeds.

Unchanged files are never downloaded again. The manager dashboard reports:

- current action and path
- progress bar
- added / changed / removed / unchanged counts
- downloaded byte count in persistent update state
- active cache slot and commit

A manager-only or documentation-only Git commit therefore downloads zero Ubuntu image files.

## Server chassis status

Ubuntu Server nodes run `cclua-statusd.service`. By default the redstone status lamp is on the bottom side of the computer:

- steady on: healthy
- slow blink: booting or updating
- fast blink: degraded / failed
- off: stopped or not initialized

The side may be overridden with `status_light_side` in `/etc/cclua/machine.json`.

## Server monitor dashboard

`dashboard.service` automatically discovers an attached monitor and displays Ubuntu Server health, services, networking, update state, manager connectivity, and the chassis lamp state. The monitor side does not need to be hard-coded.
