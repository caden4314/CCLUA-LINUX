# CCLUA NET v2

## Topology

```text
                 GitHub
                   |
              CCLUA-MANAGER
             10.27.0.1
              /   |   \
       10.27.0.11 .12 .13
        NODE-01 NODE-02 NODE-03
```

## Design goals

- deterministic addressing
- manager-based discovery and orchestration
- reliable messaging over CC:Tweaked modem/rednet primitives
- service ports
- request/response RPC
- authenticated management traffic
- node operation continues if the manager is temporarily unavailable

## Node identity

Each node stores persistent identity outside the system image:

- node UUID
- hostname
- virtual IP
- trusted manager identity
- node key material
- enrolled role

Suggested initial addresses:

- manager.cclua — 10.27.0.1
- node01.cclua — 10.27.0.11
- node02.cclua — 10.27.0.12
- node03.cclua — 10.27.0.13

## Packet envelope

```json
{
  "version": 2,
  "id": "request-id",
  "type": "request",
  "src": "10.27.0.11",
  "dst": "10.27.0.1",
  "src_port": 49152,
  "dst_port": 443,
  "ttl": 8,
  "service": "manager.api",
  "payload": {},
  "auth": {}
}
```

## Transport behaviors

Required:

- datagram transport
- retry/timeout request mode
- duplicate request suppression
- response correlation
- fragmentation/reassembly for large logical messages
- bounded queues
- flow-control/backpressure

## Service registry

Manager maintains dynamic service records:

- hostname/IP
- service name
- port
- health
- version
- last heartbeat

Nodes retain local DNS/service cache during manager outages.

## Management RPC

Initial manager operations:

- inventory
- status
- logs
- service status/start/stop/restart
- package inventory
- update check/stage/activate
- controlled reboot
- remote command/session later

## Security

Management traffic should use authenticated sessions.

Goals:

- node enrollment approval
- manager identity pinning
- replay protection
- per-session sequence counters
- integrity/authentication for control traffic

Do not place GitHub credentials on ordinary nodes.

## GitHub access

Only the manager requires GitHub credentials.

Nodes request:

- manifests
- packages
- system images
- update metadata

from the manager's authenticated cache/proxy.
