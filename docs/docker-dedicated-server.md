# Dedicated server in Docker

A non-root image runs the current Godot 4.7.2 Linux editor with `--headless -- --server`. It is not an export preset. The bare `godot -- --server` path in [Laptop dedicated server](laptop-dedicated-server.md) stays as it is.

From the repository root, on a machine that already has Docker:

```bash
docker compose up -d
docker compose logs -f
```

The log shows `Dedicated server listening on UDP port 9786`. Compose publishes that UDP port on the machine. It does not change a firewall, a VPN, or UPnP, and it does not use host networking. Do not forward the port onto a public address. Another computer on the same LAN joins the machine's LAN IPv4 at port `9786`. Two clients moving on that LAN is a manual check.

Loopback only:

```bash
FLAGORIA_PUBLISH=127.0.0.1:9786:9786 docker compose up
```

Another UDP port, inside the container and on the host:

```bash
FLAGORIA_SERVER_PORT=9799 FLAGORIA_PUBLISH=9799:9799 docker compose up
```

Join `that-ipv4:9799`.

Generation params are a read-only bind mount. The file is a map save used only for its generation parameters. Cuts, bridges, structures, and walls in it are not restored, and the server does not keep them (#15). There is no saves volume.

```bash
FLAGORIA_PARAMS_FILE=./island.json docker compose up -d
```

`docker compose stop` sends SIGTERM. The process closes ENet, prints one `Dedicated server stopped.` line, and exits 0. A joined client returns to the main menu. A crash restarts at most three times (`restart: on-failure:3`). A clean SIGTERM does not restart.

The image imports the project during the build. Its home directory is writable and is discarded with the container. The process is not root.

`tools/docker_dedicated_smoke.sh` builds the image and, on `127.0.0.1` only, joins the default port, checks a params mount on port 9799, restarts once after a kill, and checks the SIGTERM exit. It does nothing when this file is only being read.
