# Private VPN access

Friends who are not on the same LAN join the laptop dedicated server by its address on a private VPN. The game port stays off the public internet. This is a manual runbook. It does not open a port, change a firewall, create an account, or call UPnP.

The style is WireGuard: each machine has an address on a tunnel you already run. This doc does not choose a VPN company and it does not contain keys. In the steps below the addresses are placeholders: `<server-vpn-ipv4>`, `<client-a-vpn-ipv4>`, and `<client-b-vpn-ipv4>`.

## What is already proven

CI has joined the dedicated server on the IPv4 loopback address only. That run is [Docker dedicated server](docker-dedicated-server.md): host processes dialed the published loopback port, two of them saw one walk, and they rejoined within 60 seconds of `docker compose restart`. A mounted params file on the custom port delivered its generation seed. That is not a physical LAN test, not a VPN test, and not a check that a public address is refused.

## The listener is not a private network

The dedicated server has no bind flag. `start_dedicated_server` calls `create_server` with the port only, and it never calls `set_bind_ip`. The throwaway headless `create_server` on this engine recorded that socket as UDP `*:9786`, a wildcard listen. A wildcard listen is not private access. A client can reach the process on any address that routing and the host firewall deliver to that socket.

For a bare `godot -- --server` process, the owner keeps the port off the public interface with a host firewall rule. For Docker, `FLAGORIA_PUBLISH` is the host port mapping Compose already accepts. It does not change the process inside the container, which still has no bind flag. Default `9786:9786` publishes on every host IPv4 interface. That default is not private access.

This repository does not apply a firewall rule, a router forward, or UPnP. The dedicated boot path does not call UPnP.

## Bare Godot

From the repository root:

```bash
godot --headless --path . -- --server
```

The log shows `Dedicated server listening on UDP port 9786`.

A different UDP port:

```bash
godot --headless --path . -- --server --port 9799
```

On the server machine, allow that UDP port only on the VPN interface, and do not allow it on the public interface. Do not add a port forward on the router.

Each VPN client uses Main Menu Join:

- `<server-vpn-ipv4>` when the server is on port 9786
- `<server-vpn-ipv4>:9799` when the server was started with `--port 9799`

A bare address still uses port 9786. A blank field dials the name localhost, which is the machine running that client, not `<server-vpn-ipv4>`.

`--params <file>` loads generation parameters only. Cuts, bridges, structures, and walls in the file are not restored, and the server does not autosave (#15).

`kill -TERM <pid>` closes ENet, prints one `Dedicated server stopped.` line, and exits 0. A client that had joined returns to the main menu.

## Docker

Same `-- --server` process as [Docker dedicated server](docker-dedicated-server.md). Publish the host port only on the VPN address. Compose takes that as `address:host-port:container-port`.

```bash
FLAGORIA_PUBLISH=<server-vpn-ipv4>:9786:9786 docker compose up -d
```

Custom port, still only on that address. The port inside the container and the published host port are the same number:

```bash
FLAGORIA_SERVER_PORT=9799 FLAGORIA_PUBLISH=<server-vpn-ipv4>:9799:9799 docker compose up -d
```

Join `<server-vpn-ipv4>:9799`.

Generation params stay a read-only mount. They are not a saved world:

```bash
FLAGORIA_PARAMS_FILE=./island.json FLAGORIA_PUBLISH=<server-vpn-ipv4>:9786:9786 docker compose up -d
```

Cuts, bridges, structures, and walls in the file are not restored, and the server does not autosave (#15). There is no saves volume.

`docker compose stop` sends SIGTERM. One `Dedicated server stopped.` line, exit 0. A joined client returns to the main menu. The owner still sets the host firewall so the public interface does not accept that UDP port. Publishing on the VPN address does not replace that rule.

## Manual check

Not run by CI, and not run for this document. Use two clients that are on the VPN and are not on the server's LAN.

1. Both Join `<server-vpn-ipv4>`, or `<server-vpn-ipv4>:9799` if that is the port you started.
2. Both see the other player. One walks. The other sees that move.
3. Restart the server (`docker compose restart`, or stop and start the bare process). Both Join again and see each other.
4. From outside the VPN, Join the laptop's public address on that same port. The join should fail. If it succeeds, the firewall or the publish line is still exposing the port. That public-address join was not run.

Do not commit the real addresses or the WireGuard keys those machines use.
