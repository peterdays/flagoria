#!/usr/bin/env bash
# Build the dedicated image. Keeps the compose-network join, params,
# SIGTERM and one-shot restart checks, and also joins the published UDP
# port from host processes dialing 127.0.0.1 (not the compose DNS name).
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

projects=(flagoria-ds-default flagoria-ds-params flagoria-ds-restart flagoria-ds-publish)
host_pids=()
clients=(flagoria-ds-client flagoria-ds-params-client flagoria-ds-write)
cleanup() {
	local name project
	if [ "${#host_pids[@]}" -gt 0 ]; then
		kill "${host_pids[@]}" 2>/dev/null || true
	fi
	for name in "${clients[@]}"; do
		docker rm -f "$name" >/dev/null 2>&1 || true
	done
	for project in "${projects[@]}"; do
		docker compose -p "$project" down --timeout 10 >/dev/null 2>&1 || true
	done
}
trap cleanup EXIT

wait_log() {
	local target="$1" text="$2" i
	for i in $(seq 1 90); do
		if docker logs "$target" 2>&1 | grep -q "$text"; then
			return 0
		fi
		sleep 1
	done
	echo "timed out waiting for '${text}' from ${target}" >&2
	docker logs "$target" >&2 || true
	return 1
}

dump_failure() {
	local server_id="$1"
	shift
	echo "--- host name resolution ---" >&2
	getent ahosts localhost >&2 || true
	getent ahosts 127.0.0.1 >&2 || true
	echo "--- host udp sockets ---" >&2
	ss -uln >&2 || true
	echo "--- server logs ---" >&2
	docker logs "$server_id" >&2 || true
	local log
	for log in "$@"; do
		echo "--- client log ${log} ---" >&2
		cat "$log" >&2 || true
	done
}

json_field() {
	python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], ""))' "$1" "$2"
}

player_pos() {
	python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
p=(d.get("players") or {}).get(sys.argv[2])
print("" if not p else "%s %s" % (p[0], p[1]))' "$1" "$2"
}

sees_both() {
	python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
ids=[i for i in (d.get("players") or {}) if i not in ("","0","1")]
mine=str(d.get("id",""))
print("yes" if mine not in ("","0","1") and len(ids) >= 2 and mine in ids else "no")' "$1"
}

echo "== build =="
docker compose -p flagoria-ds-default build

echo "== import host project for published-port clients =="
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null
host_xdg="$(mktemp -d)"
XDG_CONFIG_HOME="${host_xdg}/c" XDG_DATA_HOME="${host_xdg}/d" XDG_CACHE_HOME="${host_xdg}/a" \
	"$GODOT" --headless --path "$ROOT" --editor --quit

echo "--- host name resolution (diagnostic; the published-port dial is 127.0.0.1) ---"
getent ahosts localhost || true
getent ahosts 127.0.0.1 || true

workdir="$(mktemp -d)"
cat >"${workdir}/join.gd" <<'EOF'
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var port := int(OS.get_environment("FLAGORIA_SERVER_PORT"))
	if port <= 0:
		port = 9786
	if change_scene_to_file("res://flagoria_main.tscn") != OK:
		quit(1)
		return
	for _i in 8:
		await process_frame
	var main = current_scene
	main.address_entry.text = "dedicated"
	main.add_player_joined(port)
	var world: Node = main.get_node("World")
	var deadline := Time.get_ticks_msec() + 30000
	var client_id := 0
	while Time.get_ticks_msec() < deadline:
		client_id = main.multiplayer.get_unique_id()
		if main.world_params != null and client_id != 1 and world.has_node(str(client_id)):
			break
		await process_frame
	if client_id <= 1 or not world.has_node(str(client_id)):
		printerr("docker client: did not join")
		quit(1)
		return
	print("DOCKER_JOINED %s seed %s" % [client_id, int(main.world_params.altitude_seed)])
	var want := int(OS.get_environment("FLAGORIA_EXPECT_SEED"))
	if want > 0 and int(main.world_params.altitude_seed) != want:
		printerr("docker client: seed %s, want %s" % [int(main.world_params.altitude_seed), want])
		quit(1)
		return
	if OS.get_environment("FLAGORIA_WAIT_MENU") != "1":
		quit(0)
		return
	deadline = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		main = current_scene
		if main == null:
			continue
		var menu := main.get_node_or_null("CanvasLayer2/MainMenu")
		var hud := main.get_node_or_null("CanvasLayer1")
		if menu != null and menu.visible and (hud == null or not hud.visible):
			print("DOCKER_MENU")
			quit(0)
			return
	printerr("docker client: main menu not back")
	quit(1)
EOF
cat >"${workdir}/write.gd" <<'EOF'
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
	if str(saved["error"]) != "":
		printerr(saved["error"])
		quit(1)
		return
	var src := ProjectSettings.globalize_path(str(saved["path"]))
	var out := "/var/lib/flagoria/map.json"
	# Version 3 saves are gzip. Reading them as text replaces bytes that are
	# not UTF-8, and the server then reports that the file is not a map save.
	var body := FileAccess.get_file_as_bytes(src)
	if body.size() < 2 or body[0] != 0x1f or body[1] != 0x8b:
		printerr("params file is not a gzip map save")
		quit(1)
		return
	var handle := FileAccess.open(out, FileAccess.WRITE)
	if handle == null:
		printerr("cannot write %s" % out)
		quit(1)
		return
	handle.store_buffer(body)
	handle.close()
	print("DOCKER_PARAMS_WRITTEN")
	quit(0)
EOF

run_client() {
	local project="$1" name="$2"
	shift 2
	docker compose -p "$project" run -d --no-deps --name "$name" \
		--entrypoint godot \
		-v "${workdir}/join.gd:/tmp/join.gd:ro" \
		"$@" \
		dedicated \
		--headless --path /opt/flagoria --script /tmp/join.gd >/dev/null
}

echo "== default port, join on the compose network, SIGTERM =="
FLAGORIA_PUBLISH=127.0.0.1:9786:9786 \
	docker compose -p flagoria-ds-default up -d --no-build
server_id="$(docker compose -p flagoria-ds-default ps -q)"
wait_log "$server_id" "Dedicated server listening on UDP port 9786"
run_client flagoria-ds-default flagoria-ds-client -e FLAGORIA_WAIT_MENU=1
wait_log flagoria-ds-client "DOCKER_JOINED"
docker compose -p flagoria-ds-default stop --timeout 15
wait_log flagoria-ds-client "DOCKER_MENU"
client_code="$(docker wait flagoria-ds-client)"
server_code="$(docker inspect -f '{{.State.ExitCode}}' "$server_id")"
stops="$(docker logs "$server_id" 2>&1 | grep -c 'Dedicated server stopped.' || true)"
if [ "$client_code" != 0 ] || [ "$server_code" != 0 ] || [ "$stops" != 1 ]; then
	echo "join/SIGTERM client ${client_code} server ${server_code} shutdown lines ${stops}" >&2
	docker logs "$server_id" >&2 || true
	docker logs flagoria-ds-client >&2 || true
	exit 1
fi
echo "compose network: joined, main menu, server exit 0, one shutdown line"

echo "== params mount, custom port =="
mkdir -p "${workdir}/out"
docker compose -p flagoria-ds-default run -d --no-deps --name flagoria-ds-write \
	--entrypoint godot \
	-v "${workdir}/write.gd:/tmp/write.gd:ro" \
	dedicated \
	--headless --path /opt/flagoria --script /tmp/write.gd >/dev/null
write_code="$(docker wait flagoria-ds-write)"
docker cp flagoria-ds-write:/var/lib/flagoria/map.json "${workdir}/out/map.json" || true
if [ "$write_code" != 0 ] || [ ! -s "${workdir}/out/map.json" ]; then
	echo "could not write a params file (exit ${write_code})" >&2
	docker logs flagoria-ds-write >&2 || true
	exit 1
fi
FLAGORIA_PUBLISH=127.0.0.1:9799:9799 \
FLAGORIA_SERVER_PORT=9799 \
FLAGORIA_PARAMS_FILE="${workdir}/out/map.json" \
	docker compose -p flagoria-ds-params up -d --no-build
server_id="$(docker compose -p flagoria-ds-params ps -q)"
wait_log "$server_id" "Dedicated server listening on UDP port 9799"
run_client flagoria-ds-params flagoria-ds-params-client \
	-e FLAGORIA_SERVER_PORT=9799 -e FLAGORIA_EXPECT_SEED=43701
wait_log flagoria-ds-params-client "DOCKER_JOINED"
if ! docker logs flagoria-ds-params-client 2>&1 | grep -q "seed 43701"; then
	echo "compose-network client did not report seed 43701" >&2
	dump_failure "$server_id"
	docker logs flagoria-ds-params-client >&2 || true
	exit 1
fi
publish_out="${workdir}/publish-9799.json"
publish_log="${workdir}/publish-9799.log"
XDG_CONFIG_HOME="${workdir}/h9799/c" XDG_DATA_HOME="${workdir}/h9799/d" XDG_CACHE_HOME="${workdir}/h9799/a" \
	"$GODOT" --headless --path "$ROOT" --script res://tests/docker_publish_probe.gd -- \
	--address=127.0.0.1 --port=9799 --out="$publish_out" >"$publish_log" 2>&1 &
host_pids+=($!)
seed_ok=0
for _ in $(seq 1 40); do
	if [ -f "$publish_out" ] && [ "$(json_field "$publish_out" seed)" = 43701 ]; then
		seed_ok=1
		break
	fi
	sleep 1
done
if [ "$seed_ok" != 1 ]; then
	echo "host client did not receive seed 43701 via published 127.0.0.1:9799" >&2
	dump_failure "$server_id" "$publish_log"
	exit 1
fi
echo "published 9799: host client endpoint $(json_field "$publish_out" endpoint) seed 43701"
kill "${host_pids[-1]}" 2>/dev/null || true
docker compose -p flagoria-ds-params stop --timeout 15
server_code="$(docker inspect -f '{{.State.ExitCode}}' "$server_id")"
if [ "$server_code" != 0 ]; then
	echo "params container SIGTERM exit ${server_code}" >&2
	exit 1
fi
echo "params mount: client received altitude seed 43701"

echo "== published UDP, two host clients, movement, compose restart =="
FLAGORIA_PUBLISH=127.0.0.1:9786:9786 \
	docker compose -p flagoria-ds-publish up -d --no-build
server_id="$(docker compose -p flagoria-ds-publish ps -q)"
if ! wait_log "$server_id" "Dedicated server listening on UDP port 9786"; then
	dump_failure "$server_id"
	exit 1
fi
start_host() {
	local out="$1" log="$2" port="$3" xdg="$4"
	mkdir -p "${xdg}/c" "${xdg}/d" "${xdg}/a"
	XDG_CONFIG_HOME="${xdg}/c" XDG_DATA_HOME="${xdg}/d" XDG_CACHE_HOME="${xdg}/a" \
		"$GODOT" --headless --path "$ROOT" --script res://tests/docker_publish_probe.gd -- \
		--address=127.0.0.1 --port="$port" --out="$out" >"$log" 2>&1 &
	host_pids+=($!)
}
both_present() {
	local a="$1" b="$2"
	[ -f "$a" ] && [ -f "$b" ] || return 1
	[ "$(sees_both "$a")" = yes ] && [ "$(sees_both "$b")" = yes ]
}
start_host "${workdir}/pub-a.json" "${workdir}/pub-a.log" 9786 "${workdir}/xa"
start_host "${workdir}/pub-b.json" "${workdir}/pub-b.log" 9786 "${workdir}/xb"
present=0
for _ in $(seq 1 45); do
	if both_present "${workdir}/pub-a.json" "${workdir}/pub-b.json"; then
		present=1
		break
	fi
	sleep 1
done
if [ "$present" != 1 ]; then
	echo "two host clients did not see each other on published 127.0.0.1:9786" >&2
	dump_failure "$server_id" "${workdir}/pub-a.log" "${workdir}/pub-b.log"
	exit 1
fi
aid="$(json_field "${workdir}/pub-a.json" id)"
start_xy="$(player_pos "${workdir}/pub-a.json" "$aid")"
moved=0
for action in ui_right ui_left ui_down ui_up; do
	printf '%s\n' "$action" >"${workdir}/pub-a.json.walk"
	for _ in $(seq 1 8); do
		now="$(player_pos "${workdir}/pub-a.json" "$aid")"
		seen="$(player_pos "${workdir}/pub-b.json" "$aid")"
		if python3 -c 'import sys; a=sys.argv[1].split(); b=sys.argv[2].split(); c=sys.argv[3].split();
import math
ok=len(a)==2 and len(b)==2 and len(c)==2 and math.dist((float(a[0]),float(a[1])),(float(b[0]),float(b[1])))>=4 and math.dist((float(b[0]),float(b[1])),(float(c[0]),float(c[1])))<1
sys.exit(0 if ok else 1)' "$start_xy" "$now" "$seen"; then
			moved=1
			break
		fi
		sleep 0.5
	done
	rm -f "${workdir}/pub-a.json.walk"
	if [ "$moved" = 1 ]; then
		break
	fi
done
if [ "$moved" != 1 ]; then
	echo "published-port clients did not observe movement of ${aid}" >&2
	dump_failure "$server_id" "${workdir}/pub-a.log" "${workdir}/pub-b.log"
	exit 1
fi
echo "published 9786: both host clients present, movement of ${aid} seen"
for pid in "${host_pids[@]}"; do
	kill "$pid" 2>/dev/null || true
done
host_pids=()
before_listen="$(docker logs "$server_id" 2>&1 | grep -c 'Dedicated server listening on UDP port 9786' || true)"
restart_started=$(date +%s)
docker compose -p flagoria-ds-publish restart --timeout 15 dedicated
server_id="$(docker compose -p flagoria-ds-publish ps -q)"
heard=0
while [ $(( $(date +%s) - restart_started )) -le 60 ]; do
	count="$(docker logs "$server_id" 2>&1 | grep -c 'Dedicated server listening on UDP port 9786' || true)"
	running="$(docker inspect -f '{{.State.Status}}' "$server_id" 2>/dev/null || true)"
	if [ "$count" -gt "$before_listen" ] && [ "$running" = running ]; then
		heard=1
		break
	fi
	sleep 1
done
if [ "$heard" != 1 ]; then
	echo "published server did not listen again after docker compose restart" >&2
	dump_failure "$server_id"
	exit 1
fi
rm -f "${workdir}/re-a.json" "${workdir}/re-b.json"
start_host "${workdir}/re-a.json" "${workdir}/re-a.log" 9786 "${workdir}/rea"
start_host "${workdir}/re-b.json" "${workdir}/re-b.log" 9786 "${workdir}/reb"
rejoined=0
while [ $(( $(date +%s) - restart_started )) -le 60 ]; do
	if both_present "${workdir}/re-a.json" "${workdir}/re-b.json"; then
		rejoined=1
		break
	fi
	sleep 1
done
if [ "$rejoined" != 1 ]; then
	echo "clients did not rejoin via published 127.0.0.1:9786 within 60s of docker compose restart" >&2
	dump_failure "$server_id" "${workdir}/re-a.log" "${workdir}/re-b.log"
	exit 1
fi
echo "published 9786: rejoin after docker compose restart in $(( $(date +%s) - restart_started ))s"
docker compose -p flagoria-ds-publish stop --timeout 15

echo "== one crash restart, then a graceful stop =="
# The entrypoint exits 1 once when FLAGORIA_CRASH_ONCE=1. A manual docker
# kill does not trip on-failure.
FLAGORIA_PUBLISH=127.0.0.1:9787:9786 \
FLAGORIA_CRASH_ONCE=1 \
	docker compose -p flagoria-ds-restart up -d --no-build
server_id="$(docker compose -p flagoria-ds-restart ps -q)"
wait_log "$server_id" "Dedicated server listening on UDP port 9786"
restarts="$(docker inspect -f '{{.RestartCount}}' "$server_id")"
if [ "$restarts" -lt 1 ] || [ "$restarts" -gt 3 ]; then
	echo "restart count ${restarts} after the one-shot exit" >&2
	docker logs "$server_id" >&2 || true
	exit 1
fi
docker update --restart=no "$server_id" >/dev/null
docker stop --time 15 "$server_id" >/dev/null
server_code="$(docker inspect -f '{{.State.ExitCode}}' "$server_id")"
status="$(docker inspect -f '{{.State.Status}}' "$server_id")"
restarts="$(docker inspect -f '{{.RestartCount}}' "$server_id")"
if [ "$server_code" != 0 ] || [ "$status" != exited ] || [ "$restarts" -lt 1 ] || [ "$restarts" -gt 3 ]; then
	echo "restart check exit ${server_code} status ${status} restarts ${restarts}" >&2
	exit 1
fi
echo "restart: listened again once, then SIGTERM stayed down (restarts ${restarts})"
echo "docker dedicated smoke: ok"
