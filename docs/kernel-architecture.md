# CCLUA Kernel Architecture

## Purpose

The CCLUA kernel is the shared runtime foundation for:

- ubuntu-22.04-server
- ubuntu-22.04-desktop
- manager

It is not a Linux kernel emulator. It is a CC:Tweaked-native kernel/runtime which exposes Linux-inspired behavior and stable CCLUA APIs.

## Kernel responsibilities

The kernel owns:

- boot/runtime initialization
- process scheduler
- PID allocation
- process lifecycle
- users/groups and execution identity
- capabilities and privilege checks
- signals
- IPC
- PTYs/terminals
- service/runtime integration hooks
- virtual filesystem dispatch
- pseudo-filesystem providers
- device/peripheral abstraction
- clock/timers
- kernel logging
- panic/recovery
- syscall/API boundary
- system information exported to /proc and /sys

The kernel should not contain high-level applications or Ubuntu-specific package behavior.

## Boot contract

```text
CraftOS startup
   |
   v
stage-0 bootstrap
   |
   v
load + verify .luaiso
   |
   v
mount active /System slot
   |
   v
kernel/init.lua
   |
   +--> runtime
   +--> scheduler
   +--> VFS
   +--> device manager
   +--> IPC
   +--> process manager
   +--> pseudo-filesystems
   |
   v
PID 1 / init
   |
   v
services + login/desktop/server role
```

The bootstrap should remain minimal. Kernel policy belongs in the kernel, not stage-0.

## Kernel module layout

Suggested source layout:

```text
kernel/
├─ init.lua
├─ runtime.lua
├─ scheduler.lua
├─ process.lua
├─ syscall.lua
├─ signals.lua
├─ capabilities.lua
├─ ipc.lua
├─ pty.lua
├─ users.lua
├─ clock.lua
├─ log.lua
├─ panic.lua
├─ vfs.lua
├─ mounts.lua
├─ device.lua
├─ procfs.lua
├─ devfs.lua
├─ sysfs.lua
└─ compat/
   └─ linux.lua
```

## Process model

Every process has a kernel-owned record.

Minimum fields:

```text
pid
ppid
name
state
uid
gid
groups
session_id
process_group
cwd
environment
capabilities
priority
created_at
started_at
ended_at
exit_code
signal
cpu/resume counters
open handles
pty
mailbox
```

### Process states

Initial states:

- new
- runnable
- running
- sleeping
- waiting
- stopped
- zombie
- exited
- killed
- crashed

The kernel should expose state transitions rather than allowing user programs to mutate process records directly.

## PID 1

PID 1 is the CCLUA init/service supervisor.

Responsibilities:

- reap exited child processes
- launch role-specific boot target
- coordinate shutdown/reboot
- receive kernel/service failures
- transition the system into rescue mode when required

The service manager may be a userspace process, but PID 1 has special lifecycle responsibilities.

## Scheduler

CC:Tweaked is cooperative, so the kernel scheduler wraps coroutines and events.

Requirements:

- deterministic PID allocation
- runnable/waiting queues
- per-process event filters
- targeted events
- timers
- sleeping processes
- process accounting
- bounded execution
- crash containment
- kill-pending handling
- fair scheduling

### Scheduling policy

Initial policy:

- cooperative round-robin
- processes yield on syscall/event wait
- kernel may impose resume/time accounting
- no process may monopolize a kernel dispatch loop indefinitely

Future policy may include simple priorities/nice values.

## Kernel/user boundary

Programs should not receive the full raw kernel context.

Userspace receives a restricted syscall/API surface.

Conceptual syscall groups:

```text
proc.*
fs.*
ipc.*
net.*
time.*
user.*
tty.*
device.*
system.*
```

The implementation may use Lua function calls internally, but the privilege boundary should be explicit and enforced.

## Syscall examples

### Process

- getpid()
- getppid()
- spawn()
- exec()
- wait()
- exit()
- kill()
- getpriority()
- setpriority()

### Filesystem

- open()
- read()
- write()
- close()
- stat()
- list()
- mkdir()
- unlink()
- rename()
- mount()
- umount()

### IPC

- pipe()
- send()
- recv()
- event()
- shared object later if useful

### Time

- uptime()
- clock()
- sleep()
- timer()

### Identity

- getuid()
- getgid()
- setuid() with privilege checks
- setgid() with privilege checks
- getgroups()

## Capabilities

Root UID alone should not be the only privilege mechanism.

Initial capability model:

- fs.read
- fs.write
- fs.mount
- proc.spawn
- proc.signal
- proc.inspect
- user.admin
- service.control
- net.bind
- net.admin
- device.access
- system.reboot
- system.update
- kernel.inspect

Capabilities may support scoped variants such as:

```text
fs.user.*
fs.system.read
net.bind.80
device.monitor.*
```

Kernel checks capability requirements on every privileged syscall.

## Signals

Initial signal set should provide familiar semantics:

- TERM
- KILL
- INT
- HUP
- STOP
- CONT
- CHLD

Signals are kernel events, not unrestricted CC events.

Behavior can be approximate where CC:Tweaked lacks preemption, but state and exit semantics should remain predictable.

## IPC

First IPC mechanisms:

1. process mailboxes
2. targeted kernel events
3. pipes
4. PTYs
5. local service sockets/ports

Every IPC object should have kernel ownership and cleanup when the owning process exits.

## PTY model

PTYs are required for:

- terminal app
- login sessions
- SSH sessions
- remote manager consoles

PTY state includes:

- rows/columns
- input queue
- output buffer
- foreground process group
- closed/eof state

Later additions:

- canonical/raw mode
- echo
- basic terminal control flags

## VFS boundary

The kernel owns the mount table and file-descriptor abstraction.

Filesystem providers implement a common contract.

Initial providers:

- imagefs
- persistfs
- procfs
- devfs
- sysfs
- tmpfs-like memory filesystem

User processes never bypass the VFS and access raw CraftOS paths directly.

## File descriptors

Each process gets an FD table.

At minimum:

- 0 stdin
- 1 stdout
- 2 stderr

FD objects may represent:

- files
- pipes
- PTYs
- devices
- sockets later

FDs must be closed automatically on process exit unless explicitly inherited.

## Device model

CC peripherals become kernel-managed devices.

Examples:

- monitors
- speakers
- modems
- drives
- printers
- generic peripherals

The kernel should expose a stable device ID/path independent of changing raw peripheral names where possible.

Devices appear through /dev and /sys.

## Pseudo-filesystems

### procfs

Kernel-backed runtime data:

- /proc/uptime
- /proc/version
- /proc/meminfo
- /proc/cpuinfo
- /proc/<pid>/status
- /proc/<pid>/cmdline
- /proc/<pid>/fd
- /proc/net

### devfs

Kernel device endpoints.

### sysfs

Structured kernel/device/service information.

These are generated dynamically and are not stored in the system image.

## Environment and exec

A process owns:

- argv
- environment table
- cwd
- uid/gid
- capabilities
- descriptors

`exec` replaces a process image while preserving PID and allowed inherited state.

Lua modules/programs are the executable format.

## Kernel modules/libraries

Kernel modules should use explicit imports and avoid unrestricted global mutation.

Suggested module contract:

```lua
return {
  name = "scheduler",
  init = function(kernel) ... end,
  shutdown = function(kernel) ... end
}
```

Core modules can use a private kernel context unavailable to userspace.

## Kernel logging

Kernel log records should include:

- timestamp
- level
- subsystem
- PID when applicable
- message
- structured details

Export through:

- kernel ring buffer
- /proc or /sys view
- journald userspace sink

## Panic handling

A kernel panic should:

1. freeze new userspace process creation
2. capture kernel state
3. write a crash report if storage is available
4. display a concise panic screen
5. mark the current boot unhealthy
6. permit automatic rollback if this is a pending A/B image
7. enter rescue/reboot flow

Panics should not silently reboot in a loop.

## Rescue mode

Minimal rescue environment should provide:

- shell
- filesystem inspection
- slot status
- log viewing
- rollback command
- networking diagnostics when possible

Rescue must work without the desktop stack.

## Shutdown/reboot

Kernel coordinates:

1. notify PID 1
2. stop services
3. TERM userspace
4. timeout
5. KILL remaining userspace
6. flush persistent state
7. commit/rollback boot metadata
8. reboot/shutdown via CraftOS

## Compatibility layer

`kernel/compat/linux.lua` exposes helper semantics used by Ubuntu-compatible userspace.

Examples:

- errno constants
- signal numbers/names
- mode bits
- UID/GID conventions
- process state formatting
- uname fields

Keep this layer separate from core scheduler/VFS internals.

## Kernel ABI versioning

Expose:

```text
kernel_abi = 1
syscall_abi = 1
vfs_abi = 1
device_abi = 1
```

Packages/images declare minimum compatible ABI versions.

Breaking changes increment the relevant ABI.

## Security rules

- no direct userspace access to kernel tables
- no raw peripheral access unless granted
- no raw CraftOS filesystem access from normal userspace
- all privileged operations checked by kernel
- process crashes must not crash the scheduler
- secrets stored outside immutable images
- manager credentials never distributed to nodes

## Non-goals for first kernel

Do not initially attempt:

- Linux ELF execution
- full POSIX compliance
- virtual memory
- preemptive multitasking
- kernel modules loaded from untrusted packages
- complex namespaces/containers
- full Unix socket API

These can be revisited only after the foundation is stable.
