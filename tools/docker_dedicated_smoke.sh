#!/usr/bin/env bash
# Build the dedicated image and check it on a compose network: a second
# container joins, a params mount changes the seed, one crash restarts,
# and SIGTERM exits 0. Does not use host networking. A client on the host
# talking to the published UDP port is not this script.
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

projects=(flagoria-ds-default flagoria-ds-params flagoria-ds-restart)
clients=(flagoria-ds-client flagoria-ds-params-client flagoria-ds-write)
cleanup() {
	local name project
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

echo "== build =="
docker compose -p flagoria-ds-default build

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
	var out := "/params/out/map.json"
	var body := FileAccess.get_file_as_string(src)
	var handle := FileAccess.open(out, FileAccess.WRITE)
	if handle == null:
		printerr("cannot write %s" % out)
		quit(1)
		return
	handle.store_string(body)
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
	-v "${workdir}/out:/params/out" \
	dedicated \
	--headless --path /opt/flagoria --script /tmp/write.gd >/dev/null
write_code="$(docker wait flagoria-ds-write)"
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
run_client flagoria-ds-params flagoria-ds-params-client -e FLAGORIA_EXPECT_SEED=43701
wait_log flagoria-ds-params-client "DOCKER_JOINED"
if ! docker logs flagoria-ds-params-client 2>&1 | grep -q "seed 43701"; then
	echo "client did not report seed 43701" >&2
	docker logs flagoria-ds-params-client >&2 || true
	exit 1
fi
docker compose -p flagoria-ds-params stop --timeout 15
server_code="$(docker inspect -f '{{.State.ExitCode}}' "$server_id")"
if [ "$server_code" != 0 ]; then
	echo "params container SIGTERM exit ${server_code}" >&2
	exit 1
fi
echo "params mount: client received altitude seed 43701"

echo "== one crash restart, then a graceful stop =="
FLAGORIA_PUBLISH=127.0.0.1:9787:9786 \
	docker compose -p flagoria-ds-restart up -d --no-build
server_id="$(docker compose -p flagoria-ds-restart ps -q)"
wait_log "$server_id" "Dedicated server listening on UDP port 9786"
docker kill -s KILL "$server_id" >/dev/null
for _ in $(seq 1 90); do
	count="$(docker logs "$server_id" 2>&1 | grep -c 'Dedicated server listening on UDP port 9786' || true)"
	if [ "$count" -ge 2 ]; then
		break
	fi
	sleep 1
done
count="$(docker logs "$server_id" 2>&1 | grep -c 'Dedicated server listening on UDP port 9786' || true)"
if [ "$count" -lt 2 ]; then
	echo "container did not listen again after a crash (count ${count})" >&2
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
