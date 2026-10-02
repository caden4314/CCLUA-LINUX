# Kernel Implementation Roadmap

The kernel is the first major implementation milestone.

## Phase K0 — Boot skeleton

Deliverables:

- stage-0 bootstrap contract
- verified .luaiso load
- kernel/init.lua
- private kernel context
- kernel logger
- panic handler
- ABI/version constants
- rescue entrypoint

Success condition:

The machine can boot an empty image into the kernel and cleanly halt/reboot or enter rescue.

## Phase K1 — Scheduler

Deliverables:

- coroutine task abstraction
- PID allocator
- runnable/waiting states
- event wait/filter
- timers/sleep
- targeted events
- process accounting
- crash containment

Tests:

- spawn 100 lightweight tasks
- deterministic exits
- one crashing task does not stop others
- TERM/KILL requests complete
- waiting tasks wake only for intended events

## Phase K2 — Process manager

Deliverables:

- process records
- parent/child relationships
- argv/env/cwd
- wait/reaping
- zombie state
- exit codes
- sessions/process groups
- signal routing

Tests:

- parent waits for child
- orphan handling
- PID 1 reaping
- signal state transitions
- process listing

## Phase K3 — Syscall + capability boundary

Deliverables:

- userspace process context
- syscall dispatch
- capability checks
- UID/GID identity
- errno/error convention

Tests:

- unprivileged process cannot mutate kernel
- denied privileged calls return stable errors
- root/capability grants behave predictably

## Phase K4 — VFS + descriptors

Deliverables:

- mount table
- filesystem provider ABI
- process FD table
- stdin/stdout/stderr
- imagefs
- persistfs
- tmpfs
- symlinks
- ownership/mode metadata

Tests:

- create/read/write/rename/delete
- FD inheritance/cleanup
- path traversal protection
- read-only image enforcement
- mount/unmount

## Phase K5 — PTY + IPC

Deliverables:

- mailboxes
- pipes
- PTYs
- process-targeted messages
- foreground process group basics

Tests:

- shell pipeline
- terminal process
- SSH-like PTY session
- cleanup on process death

## Phase K6 — Devices + pseudo-filesystems

Deliverables:

- device registry
- peripheral abstraction
- devfs
- procfs
- sysfs

Tests:

- devices appear/disappear safely
- /proc reflects live processes
- /proc/<pid>/fd matches descriptors
- /sys exposes device properties

## Phase K7 — PID 1 + service handoff

Deliverables:

- PID 1
- shutdown/reboot coordination
- service-manager userspace process
- health reporting
- rescue transition

Tests:

- service crash isolation
- orderly shutdown
- boot health commit
- pending-image failure triggers rollback state

## Phase K8 — Networking kernel boundary

Deliverables:

- network device abstraction
- socket/port ownership API
- userspace net daemon integration
- DNS/service resolver hooks

Networking policy/protocol remains largely userspace, but kernel owns process/network resource boundaries.

## Phase K9 — Ubuntu compatibility foundation

Deliverables:

- linux compatibility constants
- uname
- /proc compatibility views
- signal names
- errno map
- UID/GID conventions

This is the point where coreutils/system utilities should begin in earnest.

## First usable kernel milestone

Call the first usable kernel:

`Kernel ABI 1 / CCLUA 0.1 Foundation`

Required before declaring it usable:

- K0-K7 complete
- scheduler/process/VFS test suite passing
- terminal shell can run as userspace PID
- procfs/devfs/sysfs operational
- service manager can boot a Server image
- A/B health state can be committed
