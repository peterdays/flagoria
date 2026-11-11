# Dedicated server in Docker

A non-root image runs the current Godot 4.7.2 Linux editor with `--headless -- --server`. It is not an export preset. The bare `godot -- --server` path in [Laptop dedicated server](laptop-dedicated-server.md) stays as it is.

From the repository root, on a machine that already has Docker:

```bash
docker compose up -d
docker compose logs -f
```

The log shows `Dedicated server listening on UDP port 9786`. Compose publishes that UDP port on the machine. It does not change a firewall, a VPN, or UPnP, and it does not use host networking. Do not forward the port onto a public address. Another computer on the same LAN joins the machine's LAN IPv4 at port `9786`. Two clients moving on that LAN is a manual check. Friends off that LAN use [Private VPN access](private-server.md). Publishing `9786:9786` on every host interface is not that step.

Loopback only:

```bash
FLAGORIA_PUBLISH=127.0.0.1:9786:9786 docker compose up
```

Another UDP port, inside the container and on the host:

```bash
FLAGORIA_SERVER_PORT=9799 FLAGORIA_PUBLISH=9799:9799 docker compose up
```

Join `that-ipv4:9799`.

Generation params are a read-only bind mount. The file is a map save used only for its generation parameters. Copy the save as bytes: version 3 saves are gzip, and a text copy is not a map save. Cuts, bridges, structures, and walls in it are not restored, and the server does not keep them (#15). There is no saves volume.

```bash
FLAGORIA_PARAMS_FILE=./island.json docker compose up -d
```

`docker compose stop` sends SIGTERM. The process closes ENet, prints one `Dedicated server stopped.` line, and exits 0. A joined client returns to the main menu. A crash restarts at most three times (`restart: on-failure:3`). A clean SIGTERM does not restart. `FLAGORIA_CRASH_ONCE=1` is only for the smoke: the process exits 1 once, then the restart policy starts it. Leave it unset.

The image imports the project during the build. Its home directory is writable and is discarded with the container. The process is not root.

`tools/docker_dedicated_smoke.sh` builds the image. One client is a second container on the compose network (menu after SIGTERM, params seed, one-shot crash restart). Separately, host processes dial `127.0.0.1` on the published UDP port: two of them on 9786 see each other move, then rejoin within 60 seconds of `docker compose restart`, and one on 9799 checks the mounted seed. A blank Join field dials the name `localhost`, which is not that check. `player_joined` is printed before `create_client`, so that line alone is not a connection. The smoke prints host name resolution and, on failure, the server log and the client log. Two machines on a physical LAN were not run.
