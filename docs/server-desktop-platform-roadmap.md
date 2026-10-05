# CCLUA Server / Desktop Platform Roadmap

## Design goal

Make Server and Desktop two presentations of the same operating-system APIs rather than separate collections of scripts. GUI applications, shell commands, dashboards, remote management, and future web endpoints should consume shared structured APIs.

## Phase 1 — shared system API and operator CLI

Status: started.

- `/usr/lib/cclua/api/system.lua` provides one structured host/system/network/update/service/process snapshot.
- `/usr/bin/cclua` is the unified operator CLI.
- `/usr/bin/fastfetch` provides a familiar Linux-style host summary.
- Desktop Settings consumes the same system API.
- Existing specialized tools such as systemctl, journalctl, cclua-managerctl, cclua-lightctl, and cclua-appctl remain available.

Next API modules:
- api/services.lua
- api/network.lua
- api/packages.lua
- api/apps.lua
- api/files.lua
- api/notifications.lua
## Phase 2 — terminal jobs and PTY-like sessions

Status: foundation implemented.

The Desktop Terminal now runs external commands as scheduled kernel jobs instead of
capturing them synchronously in the compositor. The shared job/PTY path currently
provides:

- child lifecycle, process groups, foreground/background jobs, and `jobs` / `fg` / `bg`
- PTY-scoped stdin/event delivery so focused keyboard and mouse input does not leak to other jobs
- stdout/stderr terminal streams with per-cell ComputerCraft blit colour state
- terminal resizing and targeted `term_resize` delivery
- Ctrl+C / SIGINT and Ctrl+Z / SIGSTOP with SIGCONT resume semantics
- alternate-screen, cursor, cursor-blink, palette, and colour state
- Terminal-owned scrollback when PTY rows leave the child viewport
- explicit cancellation plus optional job deadlines/timeouts
- PTY inheritance for nested commands launched through the shared exec/shell paths
- immediate compositor wake-up on PTY output and process exit
- first-class process descriptors via `fd[0]`, `fd[1]`, and `fd[2]`
- descriptor syscalls for lookup, duplication, and close
- cooperative pipe streams with lifecycle wakeups and EOF
- concurrent shell pipelines plus `<`, `>`, `>>`, `2>`, `2>>`, and `2>&1`
- stream-backed terminal adapters so existing `print` / `write` programs can participate in pipelines
- stdin-aware `cat`, `grep`, `head`, `wc`, `sort`, `uniq`, `cut`, `tee`, and `tr`

First interactive ports on this foundation:
- `top`: live alternate-screen process/service view with refresh and sorting
- `less`: interactive pager with navigation and search
- `watch`: repeated command execution with inherited PTY output

Remaining Phase 2 work:
- additional shell grammar: `&&`, `||`, subshells, command substitution, variables/globbing, and ordered POSIX redirection edge cases
- bounded pipes/backpressure and richer descriptor types beyond the initial stream/file/PTY set
- user-installed signal handlers and fuller POSIX terminal modes
- improved nano-style editor and man/help database
- SSH/SCP/SFTP client sessions
- interactive apt/package operations
- richer htop-style process controls
- tmux-like persistent sessions

## Phase 3 — desktop application registry

Replace the compositor's hard-coded APP table with package/application manifests similar to Linux `.desktop` entries.

Each app manifest should expose id, name, icon, category, entry module, capabilities, supported roles, file/MIME associations, and optional command-line aliases.

This allows installed packages to add desktop applications without editing the compositor.
## Phase 4 — desktop UX

- command palette for apps, commands, settings, files, and fleet actions
- notification/toast center backed by api/notifications.lua
- consistent destructive-action confirmations
- loading/progress states for network and package work
- keyboard focus model and accessibility shortcuts
- window snap/tiling presets
- better compact/wide responsive layouts
- unified error objects with user message, technical detail, remediation, and log reference

## Phase 5 — Linux application ports

Prioritize applications that fit ComputerCraft constraints instead of imitating programs that fundamentally require a browser or GPU stack.

Foundation:
- man/help database
- tree, file, diff, tar/archive manager
- improved nano/text editor
- htop/system monitor
- fastfetch
- SSH/SCP/SFTP

Desktop:
- Files/Nautilus improvements
- Terminal
- Text Editor
- System Monitor
- Software/package manager
- Settings/Control Center
- log viewer / journal application
- network manager UI

Server:
- service manager TUI
- deployment/app-host console
- fleet dashboard
- logs/events console
- package/update console
- network diagnostics
## Phase 6 — remote/API surface

Expose selected shared APIs through authenticated CCLUA NET RPC first. Add HTTP only where it provides clear value.

Requirements:
- typed/schema-versioned requests and responses
- capability/permission checks
- request IDs and structured errors
- timeouts/cancellation
- audit logging for mutations
- read-only status endpoints separated from control actions

This becomes the basis for a web admin UI, server automation, and management from other CCLUA computers without duplicating business logic.

## Acceptance principles

- CLI and GUI show the same underlying state.
- APIs return structured data; presentation code formats it.
- a failed service/network/update action always provides a useful remediation path.
- desktop apps remain responsive while jobs/network requests run.
- imported Linux applications behave consistently with familiar Linux conventions where ComputerCraft permits it.
- server roles remain fully usable without a graphical desktop.
