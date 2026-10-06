# CCPerf Native Runtime Plan

CCPerf is the optional native capability layer below CCLUA-LINUX. CCLUA must
remain bootable on stock CC:Tweaked, but when CCPerf is present the kernel may
use lower-latency and higher-throughput primitives.

## Design boundary

Keep policy in Lua. Put mechanisms in Java only when they need:
- timing finer than normal ComputerCraft timers;
- large binary processing which is expensive in Lua;
- Minecraft/client renderer access unavailable through public Lua APIs;
- OpenAL/audio scheduling;
- CC:Tweaked packet-network integration;
- work which would otherwise monopolize the cooperative Lua scheduler.

Prefer CC:Tweaked public APIs first. Use mixins only for internals which the
public API cannot expose.

The supported 1.20.1 API provides:
- ComputerCraftAPI.registerAPIFactory / ILuaAPI for a native CCLUA module;
- IComputerSystem for ID, label, level, position and attached peripherals;
- WorkMonitor for fair accounting of native work;
- PacketNetwork / PacketReceiver for native network integration;
- ByteBuffer conversion for binary Lua strings.

Mixins remain appropriate for monitor renderer and speaker/OpenAL internals.

## Native API v1

Global/module: ccperf

Implemented:
- version()
- capabilities()
- computer()
- monotonicMicros()
- epochMillis()
- startTimer(seconds)
- cancelTimer(id)

Cclua wrapper: /usr/lib/cclua/native.lua.

The kernel scheduler automatically uses native timers when present and falls
back to os.startTimer otherwise.

## Next native primitives

### Binary/codec
- crc32(data)
- sha256(data)
- deflate(data, level)
- inflate(data, maxBytes)
- optional zstd only if a small, maintained dependency is acceptable

Use for update transfer validation/compression, package caches and media chunks.
All operations need strict maximum sizes and WorkMonitor/time accounting.

### Native network
Build a CCLUA virtual NIC using CC:Tweaked PacketNetwork rather than bypassing
ComputerCraft networking.
- framed payloads with protocol/version/type/sequence
- RX ring and bounded TX queue
- counters, drops, RTT and queue depth
- optional reliable stream on top of packets
- event: ccperf_net
- retain normal modem/rednet fallback

This should back CCLUA NET eventually, while rednet remains the compatibility
transport.

### Display
Turn the current RGB framebuffer into a general display surface:
- persistent surfaces and texture reuse
- sequence/timestamp on present
- latest-frame mailbox
- dirty rectangles
- RGB888 initially; RGB565/indexed modes for bandwidth-sensitive displays
- client timing/queue/drop counters
- optional double-buffered present-at timestamp
- terminal remains available as the compatibility plane

### Audio
Move theater-specific raw PCM support into a generic native audio stream API:
- explicit stream/group handles
- shared sample clock
- queue depth and underrun counters
- synchronized start epoch for N speakers
- bounded queue, no Lua-side blocking
- per-stream gain and optional positional source control
- events for low-water/underrun instead of polling speaker_audio_empty

### Scheduler/runtime
- native timers (implemented)
- high-resolution monotonic clock (implemented)
- optional native worker jobs for codec/hash operations
- bounded completion events
- expose timing/queue telemetry, never arbitrary Java execution

## CCLUA streamlining

### Kernel
- one platform/native abstraction (native.lua)
- event-driven state notifications instead of repeated JSON polling
- shared cached machine/peripheral/network snapshots
- native timers where available
- keep services cooperative and bounded

### Server profile
- no compositor unless requested
- lazy-load interactive apps
- manager/network/update services stay resident
- consolidate status/peripheral snapshots
- use compressed delta transfers when native codec is available

### Desktop profile
- compositor stays resident but redraw only dirty windows/regions
- apps start on demand
- background apps stop rendering while hidden/minimized
- central clock/status notifications rather than each app owning timers
- cache peripheral and network inventory through one service

### Services
Manager/update/network currently have legitimate long-period health polling.
Keep those safety polls, but use events for immediate changes. Avoid multiple
sub-second polling loops reading the same JSON files.

## Safety/stability rules

- No arbitrary host filesystem or command execution through ccperf.
- No general Java reflection API.
- Every native buffer/queue has a hard size limit.
- Native work must be bounded and accounted where applicable.
- Capability probing is mandatory; stock CC:Tweaked fallback must continue.
- Keep public CC:Tweaked API hooks version-stable; isolate mixins behind runtime
  validation and fail closed when their targets change.
- Client-only capabilities must never be required for server boot.
