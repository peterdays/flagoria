#!/usr/bin/env bash
# Build the dedicated image and, on loopback only, join it, check a params
# mount, restart once after a crash, and stop with SIGTERM.
# Not a LAN test. Exits non-zero when docker is missing or a check fails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v docker >/dev/null 2>&1; then
	echo "docker dedicated smoke: docker is not on PATH" >&2
	exit 1
fi
if ! docker info >/dev/null 2>&1; then
	echo "docker dedicated smoke: docker is installed but the daemon is not reachable" >&2
	exit 1
fi

GODOT="${GODOT:-godot}"
projects=(flagoria-ds-default flagoria-ds-params flagoria-ds-restart)
client=0
cleanup() {
	local project
	if [ "$client" != 0 ]; then
		kill "$client" 2>/dev/null || true
	fi
	for project in "${projects[@]}"; do
		docker compose -p "$project" down --timeout 10 >/dev/null 2>&1 || true
	done
}
trap cleanup EXIT

echo "== import host project for the joining client =="
host_xdg="$(mktemp -d)"
XDG_CONFIG_HOME="${host_xdg}/c" XDG_DATA_HOME="${host_xdg}/d" XDG_CACHE_HOME="${host_xdg}/a" \
	"$GODOT" --headless --path "$ROOT" --editor --quit

echo "== build =="
docker compose -p flagoria-ds-default build

wait_log() {
	local project="$1" text="$2" i
	for i in $(seq 1 90); do
		if docker compose -p "$project" logs 2>&1 | grep -q "$text"; then
			return 0
		fi
		sleep 1
	done
	echo "timed out waiting for '${text}' from ${project}" >&2
	docker compose -p "$project" logs >&2 || true
	return 1
}

echo "== default port, join, SIGTERM =="
FLAGORIA_PUBLISH=127.0.0.1:9786:9786 \
	docker compose -p flagoria-ds-default up -d --no-build
wait_log flagoria-ds-default "Dedicated server listening on UDP port 9786"

status="$(mktemp)"
xdg="$(mktemp -d)"
XDG_CONFIG_HOME="${xdg}/c" XDG_DATA_HOME="${xdg}/d" XDG_CACHE_HOME="${xdg}/a" \
	"$GODOT" --headless --path "$ROOT" --script res://tests/server_quit_probe.gd -- \
	--port=9786 --status="$status" >/tmp/flagoria-ds-client.log 2>&1 &
client=$!
joined=0
for _ in $(seq 1 90); do
	if [ -f "$status" ] && grep -q joined "$status"; then
		joined=1
		break
	fi
	if ! kill -0 "$client" 2>/dev/null; then
		break
	fi
	sleep 1
done
if [ "$joined" != 1 ]; then
	echo "client did not join the container" >&2
	cat /tmp/flagoria-ds-client.log >&2 || true
	exit 1
fi
docker compose -p flagoria-ds-default stop --timeout 15
wait "$client"
if ! grep -q menu "$status"; then
	echo "client did not return to the main menu" >&2
	cat /tmp/flagoria-ds-client.log >&2 || true
	exit 1
fi
cid="$(docker compose -p flagoria-ds-default ps -a -q | head -n 1)"
code="$(docker inspect -f '{{.State.ExitCode}}' "$cid")"
stops="$(docker compose -p flagoria-ds-default logs 2>&1 | grep -c 'Dedicated server stopped.' || true)"
if [ "$code" != 0 ] || [ "$stops" != 1 ]; then
	echo "SIGTERM exit ${code}, shutdown lines ${stops}" >&2
	docker compose -p flagoria-ds-default logs >&2 || true
	exit 1
fi
echo "default port: joined, main menu, exit 0, one shutdown line"

echo "== params mount, custom port =="
params_dir="$(mktemp -d)"
export XDG_CONFIG_HOME="${params_dir}/c" XDG_DATA_HOME="${params_dir}/d" XDG_CACHE_HOME="${params_dir}/a"
cat >"${params_dir}/write.gd" <<'EOF'
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var params := MapGenParams.make_defaults()
	params.altitude_seed = 43701
	params.moisture_seed = 43702
	params.temperature_seed = 43703
	params.items_seed = 43704
	params.biome_seed = 43705
	params.ensure_seeds()
	var saved := MapSave.save_map(params, "docker_params")
	if saved["error"] != "":
		printerr(saved["error"])
		quit(1)
		return
	print("DOCKER_PARAMS_PATH %s" % ProjectSettings.globalize_path(saved["path"]))
	quit(0)
EOF
params_path="$("$GODOT" --headless --path "$ROOT" --script "${params_dir}/write.gd" | awk '/^DOCKER_PARAMS_PATH / {print $2}')"
if [ ! -s "$params_path" ]; then
	echo "could not write a params file" >&2
	exit 1
fi
FLAGORIA_PUBLISH=127.0.0.1:9799:9799 \
FLAGORIA_SERVER_PORT=9799 \
FLAGORIA_PARAMS_FILE="$params_path" \
	docker compose -p flagoria-ds-params up -d --no-build
wait_log flagoria-ds-params "Dedicated server listening on UDP port 9799"
cat >"${params_dir}/join.gd" <<'EOF'
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var port := 9799
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		quit(1)
		return
	for _i in 3:
		await process_frame
	current_scene.add_player_joined(port)
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		var params = current_scene.world_params
		if params != null and int(params.altitude_seed) == 43701:
			print("DOCKER_SEED %s" % int(params.altitude_seed))
			quit(0)
			return
		await process_frame
	printerr("params seed did not arrive")
	quit(1)
EOF
XDG_CONFIG_HOME="${params_dir}/c2" XDG_DATA_HOME="${params_dir}/d2" XDG_CACHE_HOME="${params_dir}/a2" \
	"$GODOT" --headless --path "$ROOT" --script "${params_dir}/join.gd"
docker compose -p flagoria-ds-params stop --timeout 15
cid="$(docker compose -p flagoria-ds-params ps -a -q | head -n 1)"
code="$(docker inspect -f '{{.State.ExitCode}}' "$cid")"
if [ "$code" != 0 ]; then
	echo "params container SIGTERM exit ${code}" >&2
	exit 1
fi
echo "params mount: client received altitude seed 43701"

echo "== one crash restart, then a graceful stop =="
FLAGORIA_PUBLISH=127.0.0.1:9787:9786 \
	docker compose -p flagoria-ds-restart up -d --no-build
wait_log flagoria-ds-restart "Dedicated server listening on UDP port 9786"
cid="$(docker compose -p flagoria-ds-restart ps -q)"
docker kill -s KILL "$cid" >/dev/null
for _ in $(seq 1 90); do
	count="$(docker compose -p flagoria-ds-restart logs 2>&1 | grep -c 'Dedicated server listening on UDP port 9786' || true)"
	if [ "$count" -ge 2 ]; then
		break
	fi
	sleep 1
done
count="$(docker compose -p flagoria-ds-restart logs 2>&1 | grep -c 'Dedicated server listening on UDP port 9786' || true)"
if [ "$count" -lt 2 ]; then
	echo "container did not listen again after a crash (count ${count})" >&2
	docker compose -p flagoria-ds-restart logs >&2 || true
	exit 1
fi
docker update --restart=no "$cid" >/dev/null
docker stop --time 15 "$cid" >/dev/null
code="$(docker inspect -f '{{.State.ExitCode}}' "$cid")"
status="$(docker inspect -f '{{.State.Status}}' "$cid")"
restarts="$(docker inspect -f '{{.RestartCount}}' "$cid")"
if [ "$code" != 0 ] || [ "$status" != exited ] || [ "$restarts" -lt 1 ] || [ "$restarts" -gt 3 ]; then
	echo "restart check exit ${code} status ${status} restarts ${restarts}" >&2
	exit 1
fi
echo "restart: listened again once, then SIGTERM stayed down (restarts ${restarts})"
echo "docker dedicated smoke: ok"
