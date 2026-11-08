#!/bin/sh
# Dedicated server inside the image. PID 1 is Godot, so SIGTERM reaches the
# Linux helper shipped with the project. Generation params only: a mounted
# file is passed to --params and is not a world restore.
set -eu

# Smoke only. The file lives in the container home, so a restart of the
# same container continues into the server instead of exiting again.
if [ "${FLAGORIA_CRASH_ONCE:-}" = 1 ] && [ ! -f "${HOME}/crashed-once" ]; then
	touch "${HOME}/crashed-once"
	echo "dedicated server: exiting once so the restart policy can run" >&2
	exit 1
fi

port="${FLAGORIA_SERVER_PORT:-9786}"
case "$port" in
	''|*[!0-9]*)
		echo "FLAGORIA_SERVER_PORT must be a number from 1 to 65535" >&2
		exit 1
		;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
	echo "FLAGORIA_SERVER_PORT must be a number from 1 to 65535" >&2
	exit 1
fi

set -- --server --port "$port"
params="${FLAGORIA_PARAMS:-}"
if [ -n "$params" ]; then
	if [ ! -s "$params" ]; then
		echo "FLAGORIA_PARAMS is set but ${params} is missing or empty" >&2
		exit 1
	fi
	set -- "$@" --params "$params"
fi

exec godot --headless --path /opt/flagoria -- "$@"
