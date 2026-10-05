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

The current desktop Terminal captures command output synchronously. This is good for short commands but prevents a true interactive Unix application model.

Add a virtual terminal/job abstraction with:
- child process lifecycle and process groups
- stdin/stdout/stderr streams
- foreground/background jobs
- terminal resize events
- signals / Ctrl+C / Ctrl+Z semantics
- alternate-screen support
- cursor/colour/blit state
- scrollback owned by the terminal emulator rather than the child

Once this exists, port or improve:
- nano-style editor
- htop/top interactive mode
- less and man pager
- ssh/scp/sftp client sessions
- watch
- interactive apt/package operations
- tmux-like session persistence later

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
