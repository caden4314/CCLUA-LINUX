# CCLUA / CC:Tweaked Runtime Tuning

## Execution model

CC:Tweaked's `computer_threads` is a shared executor pool for all ComputerCraft computers.
It is not a thread count per computer.

Each CCLUA machine runs inside one CC:Tweaked computer execution context. CCLUA processes
are cooperative Lua coroutines scheduled by `src/kernel/scheduler.lua`; they are not native
JVM threads.

For the current NEWMAIN host (Ryzen 7 5800X, 8 cores / 16 logical processors), the deployment
keeps:

```toml
[execution]
computer_threads = 4
max_main_global_time = 10
max_main_computer_time = 5
```

Four computer threads gives the fleet concurrent execution without oversubscribing the
Minecraft server. Raising this value should not be used to fix a slow individual Lua task.

The two `max_main_*` values budget work which must run on Minecraft's main server thread.
They do not increase Lua CPU time and should remain conservative to protect tick time.

## CCLUA scheduling rules

- Services should wait only for events they consume.
- Request timeout timers must be cancelled when a response arrives.
- The kernel scheduler must maintain one wake timer for the nearest sleeping process rather
  than creating a new timer after every unrelated event.
- High-frequency progress should remain in memory and be persisted at a bounded cadence.
- Fleet peer snapshots are batched; protocol packets must not synchronously rewrite the full
  peer database.

## Fleet cadence

Current target values:

- CCLUA NET heartbeat: 8 seconds
- network peer snapshot: 5 seconds
- node update recovery poll: 12 seconds
- manager GitHub poll: 10 seconds
- manager idle image announcement: 20 seconds
- update staging is still announced immediately when a new image is discovered

These values keep recovery quick without leaving the fleet permanently in CHECKING traffic.
