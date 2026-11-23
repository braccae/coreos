# Workstation (Bazzite / Fedora) — KDE Plasma bootc desktop image with ZFS kmods.
ARG KMODS_IMAGE=ghcr.io/braccae/kmods:latest

FROM ghcr.io/ublue-os/bazzite:stable-45 AS base
FROM ${KMODS_IMAGE} AS kmods

FROM base AS final
ARG TARGETARCH
LABEL containers.bootc 1

# --- Repositories & workstation package groups ------------------------------
# Bind-mount build/justfile and repos/ so no build-time scripts, unused repo
# files (wazuh/crowdsec/proxmox/adoptium), or temp artifacts land in the image.
# All package groups share a single DNF metadata pass and clean caches in-layer.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,source=repos,target=/tmp/repos \
    dnf5 install -y qemu-guest-agent just && \
    just -f /tmp/build.justfile setup-repos ublue /tmp/repos && \
    just -f /tmp/build.justfile install-java && \
    just -f /tmp/build.justfile install-misc-tools && \
    just -f /tmp/build.justfile install-virt-tools && \
    just -f /tmp/build.justfile install-dev-mode && \
    just -f /tmp/build.justfile install-kde-utils && \
    just -f /tmp/build.justfile install-cloudflare-warp false && \
    just -f /tmp/build.justfile cleanup-dnf

# --- ZFS kernel modules & initramfs -----------------------------------------
# Bind-mount the prebuilt kmods tree so RPMs are never copied into a layer.
# install-zfs-kmods runs depmod and rebuild-initramfs only when the kmods match
# the active kernel.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,from=kmods,source=/zfs/bazzite,target=/tmp/kmods \
    just -f /tmp/build.justfile install-zfs-kmods "/tmp/kmods/${TARGETARCH}" bazzite && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Local rootfs overlays (late for optimal layer caching) -----------------
COPY rootfs/btrfs_config/ /
COPY rootfs/workstation/ /

# --- Final service enablement & bootc lint ----------------------------------
RUN systemctl enable tailscaled && \
    bootc container lint

ENTRYPOINT [ "/sbin/init" ]