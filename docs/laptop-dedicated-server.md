# Laptop dedicated server

Run a headless dedicated server on a laptop and join it from another machine on the same LAN. This is a manual check. CI only joins `127.0.0.1`.

From the repository root, with Godot 4.7 on `PATH`:

```bash
godot --headless --path . -- --server
```

The log shows:

```text
Dedicated server listening on UDP port 9786
```

On another computer on the same LAN, Main Menu Join uses that laptop's IPv4 address and port `9786`. The address is the LAN interface (often `192.168.x.x` or `10.x.x.x`; `ip -4 addr` lists them). Do not publish that port on a public address. This path does not change a firewall or a VPN, and it does not call UPnP.

A different UDP port is the `--port` flag:

```bash
godot --headless --path . -- --server --port 9799
```

Join `that-ipv4:9799`. A bare address still uses port `9786`.

Stop the server with SIGTERM:

```bash
kill -TERM <pid>
```

The process closes ENet, prints one line `Dedicated server stopped.`, and exits 0. A client that joined through `add_player_joined` returns to the main menu within a few seconds.

`--params <file>` loads generation parameters only. Cuts, bridges, structures, and walls in the file are not restored, and the server does not autosave. Putting a changed world back is #15.

The SIGTERM helper is `addons/server_shutdown/`. Rebuild the Linux library, if needed, with:

```bash
gcc -shared -fPIC -O2 -o addons/server_shutdown/libserver_shutdown.so addons/server_shutdown/server_shutdown.c
```
