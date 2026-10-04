# CCLUA fleet operations

## Chassis fault lamp

The chassis lamp is a fault indicator, not a normal power indicator.

- Off: healthy, booting, or updating.
- 1 blink: one or more CCLUA services failed.
- 2 blinks: update or rollback failure.
- 3 blinks: manager/network communication fault.
- 4 blinks: role hardware fault, such as missing lighting relays.

The code repeats after a pause. The same code and reason are written to
`/var/lib/cclua/status.json` and `/var/log/cclua/health.json`.

## Lighting controller

The `lighting-controller` role runs `cclua-lightingd.service`.

Management traffic uses the wireless modem when one is available. Wired modems
remain available as peripheral buses for redstone relays.

The physical lever defaults to the computer's `front` redstone input. A lever
state change immediately applies that state to all discovered lighting relays.
Wireless commands may still change the lights; the lever reasserts itself only
when the lever is physically moved.

Manager commands:

```
cclua-lightctl status
cclua-lightctl discover
cclua-lightctl on
cclua-lightctl off
cclua-lightctl animate
cclua-lightctl rooms
cclua-lightctl room Hallway status
cclua-lightctl room Hallway on
cclua-lightctl room Hallway off
cclua-lightctl room SRV status
cclua-lightctl room SRV on
cclua-lightctl room SRV off
cclua-lightctl room SRV animate
cclua-lightctl set redstone_relay_4 on
```

Lighting rooms are configured in `/etc/cclua/lighting.json`. Room commands only
touch the relays assigned to that room. When a lighting monitor is configured,
the lighting controller renders a dedicated touch UI and each room button
toggles that room independently. Room states are persisted across automatic
updates and reboots. A lever input is optional and can be disabled with
`lever_enabled=false`.

## Central app deployment

The `app-server` role runs `cclua-apphostd.service` and stores production
apps under `/srv/cclua/apps`.

On the network manager, place source packages under:

```
/srv/cclua/deploy/<app>/
```

Every package requires `app.lua`. Deploy with:

```
cclua-appctl deploy <app>
cclua-appctl deploy <app> /custom/source/path
cclua-appctl deploy <app> --start
```

Deployments are staged first, transferred in 4 KiB chunks, verified for file and
byte counts, and then swapped into production. The previous version is kept for
rollback.

Runtime controls:

```
cclua-appctl list
cclua-appctl start <app>
cclua-appctl stop <app>
cclua-appctl restart <app>
cclua-appctl rollback <app>
cclua-appctl remove <app>
```
