# Webtop (Fedora / Bazzite) — remote KDE Plasma desktop streamed with Selkies.
FROM ghcr.io/ublue-os/bazzite:stable-44 AS plasma-nm-builder

# plasma-nm 6.7.5 draws "network-unavailable" for Tun/Veth devices, which is
# exactly what a container uplink is (pasta tap / netavark veth). Separate the
# heavy SRPM + builddep layer from patching/building so patch changes reuse
# cached build dependencies.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    (command -v just >/dev/null 2>&1 || dnf5 install -y just) && \
    just -f /tmp/build.justfile prepare-plasma-nm-builddeps && \
    just -f /tmp/build.justfile cleanup-dnf

RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,source=build/plasma-nm,target=/tmp/plasma-nm \
    just -f /tmp/build.justfile build-plasma-nm /tmp/plasma-nm

# Dogfood the published workstation image (same bazzite base plus this
# repository's desktop configuration) instead of the bare ublue base.
FROM ghcr.io/braccae/workstation:latest AS base

USER root

# --- System runtime deps, patched plasma-nm, and Cloudflare WARP ------------
# Bind-mount the built plasma-nm RPMs directly from the builder stage so zero
# intermediate RPM artifacts enter any layer.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,from=plasma-nm-builder,source=/tmp/rpmbuild/RPMS,target=/tmp/plasma-nm-rpms \
    just -f /tmp/build.justfile install-webtop-fedora-deps && \
    just -f /tmp/build.justfile install-plasma-nm /tmp/plasma-nm-rpms && \
    just -f /tmp/build.justfile install-cloudflare-warp true && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Selkies 2.1 streaming server & native interposers ----------------------
# Native input/webcam interposers come from the linuxserver reference image,
# which runs the same selkies 2.1 release. The python tree and static dashboard
# are NOT copied: the venv pins selkies/pixelflux/pcmflux and selkies serves
# its own bundled dashboard.
COPY --from=lscr.io/linuxserver/webtop:fedora-kde \
     /usr/lib/selkies_input_interposer.so \
     /usr/lib/selkies_v4l2_interposer.so \
     /usr/lib/
COPY --from=lscr.io/linuxserver/webtop:fedora-kde \
     /opt/lib/libudev.so.1.0.0-fake \
     /opt/lib/

RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-selkies 2.1.0 false && \
    ln -sf selkies_input_interposer.so /usr/lib/selkies_joystick_interposer.so

# Interposer and capture defaults shared by the session launcher.
ENV SELKIES_INTERPOSER=/usr/lib/selkies_input_interposer.so \
    SELKIES_WEBCAM_INTERPOSER=/usr/lib/selkies_v4l2_interposer.so \
    PIXELFLUX_WAYLAND=true

# --- Local overlays (late for optimal layer caching) ------------------------
COPY rootfs/common/ /
COPY rootfs/webtop/ /

# --- Final webtop configuration ---------------------------------------------
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile configure-webtop-fedora

ENTRYPOINT [ "/usr/lib/systemd/systemd" ]
