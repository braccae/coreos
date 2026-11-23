FROM ghcr.io/braccae/alma:latest
LABEL containers.bootc 1

# --- k3s-selinux, NFS/idmap utilities, k3s binary, factory /etc, and lint ---
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-k3s && \
    just -f /tmp/build.justfile cleanup-dnf && \
    just -f /tmp/build.justfile snapshot-factory-etc && \
    bootc container lint
