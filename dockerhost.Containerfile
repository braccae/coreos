FROM ghcr.io/braccae/alma:latest AS base

FROM base AS builder

# --- Build cockpit-docker RPM from source -----------------------------------
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile build-cockpit-docker /tmp/cockpit-docker-rpms && \
    just -f /tmp/build.justfile cleanup-dnf

FROM base AS final
LABEL containers.bootc 1

# --- Install Docker CE + cockpit-docker RPM, refresh factory /etc, and lint -
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,from=builder,source=/tmp/cockpit-docker-rpms,target=/tmp/cockpit-docker-rpms \
    just -f /tmp/build.justfile install-docker && \
    just -f /tmp/build.justfile install-cockpit-docker /tmp/cockpit-docker-rpms && \
    just -f /tmp/build.justfile cleanup-dnf && \
    just -f /tmp/build.justfile snapshot-factory-etc && \
    bootc container lint