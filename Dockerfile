# Official Godot 4.7.2 editor binary, started with --headless. Not an export preset.
FROM ubuntu:24.04

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		unzip \
		libfontconfig1 \
		libdbus-1-3 \
		libsystemd0 \
		libudev1 \
		procps \
	&& rm -rf /var/lib/apt/lists/*

ARG GODOT_VERSION=4.7.2
RUN curl -fsSL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& install -m 755 "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
	&& rm -rf /tmp/godot /tmp/godot.zip \
	&& godot --version

# Ubuntu's image already has uid 1000. This account is only the server process.
RUN useradd --create-home --home-dir /var/lib/flagoria --uid 10001 flagoria \
	&& mkdir -p /params \
	&& chown flagoria:flagoria /params

WORKDIR /opt/flagoria
COPY --chown=flagoria:flagoria . /opt/flagoria
# WORKDIR creates this directory as root. Import has to add .godot here.
RUN chown flagoria:flagoria /opt/flagoria \
	&& chmod 755 /opt/flagoria/docker/entrypoint.sh

USER flagoria
ENV HOME=/var/lib/flagoria \
	XDG_DATA_HOME=/var/lib/flagoria/.local/share \
	XDG_CONFIG_HOME=/var/lib/flagoria/.config \
	XDG_CACHE_HOME=/var/lib/flagoria/.cache

# Import once, as the user that will run the server, so the image already has .godot.
RUN godot --headless --path /opt/flagoria --editor --quit

EXPOSE 9786/udp
ENTRYPOINT ["/opt/flagoria/docker/entrypoint.sh"]
