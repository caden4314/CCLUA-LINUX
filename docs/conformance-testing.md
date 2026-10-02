# Conformance Testing

## Goal

CCLUA programs should be tested against documented Ubuntu-like behavior instead of judged visually.

## Test record

Each compatibility test should define:

- command/service
- reference Ubuntu release
- invocation
- fixture/filesystem state
- expected stdout pattern
- expected stderr pattern
- expected exit code
- expected filesystem changes
- supported deviation notes

## Test categories

### CLI

Examples:

```text
ls
ls -la /tmp
uname -a
id
hostnamectl
grep PATTERN file
```

### Services

Check:

- enable/disable
- start/stop/restart
- dependency ordering
- failure/restart behavior
- logs

### Filesystem

Check:

- path normalization
- symlinks
- ownership/permissions
- pseudo-filesystems
- mount behavior

### Networking

Check:

- addressing
- DNS
- connection lifecycle
- timeouts
- port binding
- manager loss/recovery

### Packages

Check:

- dependency resolution
- install/remove
- config preservation
- interrupted transaction recovery

## Result states

- pass
- partial
- expected-deviation
- fail
- not-implemented

## Automation

The test harness should eventually run in CraftOS-PC and in the real Minecraft CC:Tweaked development world.

Every package/command can publish a compatibility percentage based on explicit tests, not guessed feature completeness.
