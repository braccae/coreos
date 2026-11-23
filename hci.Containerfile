FROM ghcr.io/braccae/alma:latest
LABEL containers.bootc 1

# --- Virtualization stack, NFS/idmap utilities, and Cockpit HCI plugins -----
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-hci-virt && \
    just -f /tmp/build.justfile install-cockpit hci && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Local rootfs overlay (late for optimal layer caching) ------------------
COPY rootfs/hci/ /

# --- Final configuration, factory /etc snapshot, and bootc lint -------------
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    systemctl enable tailscaled && \
    just -f /tmp/build.justfile snapshot-factory-etc && \
    bootc container lint
