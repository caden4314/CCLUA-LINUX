# Kernel Test Plan

Kernel tests should run in two environments:

1. CraftOS-PC for fast automated iteration.
2. Real Minecraft + CC:Tweaked for integration/peripheral behavior.

## Required suites

- boot
- scheduler
- processes
- signals
- capabilities
- VFS
- file descriptors
- IPC
- PTY
- pseudo-filesystems
- devices
- panic/recovery
- shutdown
- A/B boot health

## Test output

Every test should emit machine-readable results plus a concise terminal summary.

Suggested result record:

```json
{
  "suite": "scheduler",
  "test": "crash-isolation",
  "status": "pass",
  "duration_ms": 12,
  "details": {}
}
```

## Regression rule

No kernel ABI feature is considered implemented until it has at least one automated test.

Critical kernel paths should have both success and failure-path tests.
