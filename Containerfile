ARG KMODS_IMAGE=localhost/kmods:latest
FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base

FROM ${KMODS_IMAGE} AS kmods

FROM base AS final
ARG TARGETARCH
LABEL containers.bootc 1

# --- Repositories & build runner (just) -------------------------------------
# Bootstrap EPEL + `just` first, then configure RPMFusion, Tailscale, WARP,
# CrowdSec, and Wazuh repos via build/justfile.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,source=repos,target=/tmp/repos \
    dnf install -y --nogpgcheck \
        "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" && \
    dnf install -y just && \
    just -f /tmp/build.justfile setup-repos alma /tmp/repos && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Core OS RPMs: base utilities, Cockpit, SELinux tools, Podman + krun ----
# Chained in one RUN so all RPM groups share a single DNF metadata pass.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-base-packages && \
    just -f /tmp/build.justfile install-cockpit base && \
    just -f /tmp/build.justfile install-selinux-tools && \
    just -f /tmp/build.justfile install-podman-krun && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Third-party security & networking RPMs (Wazuh, CrowdSec, WARP) ---------
# Separated from core OS RPMs so third-party repo updates don't invalidate the
# core OS layer; warp-svc is left disabled until an operator opts in.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-wazuh && \
    just -f /tmp/build.justfile install-crowdsec && \
    just -f /tmp/build.justfile install-cloudflare-warp false && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Upstream CLI installers (uv, rclone, Hermes Agent CLI) -----------------
# HERMES_HOME is baked into the image env so the sealed dependency environment
# resolves for a bare `podman run ... hermes`, not just a login shell.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-uv && \
    just -f /tmp/build.justfile install-rclone && \
    just -f /tmp/build.justfile install-hermes
ENV HERMES_HOME=/usr/local/lib/hermes-agent

# --- ZFS kernel modules, Cockpit ZFS Manager, and initramfs rebuild ---------
# Bind-mount the prebuilt kmods tree so RPMs are never copied into a layer.
# install-zfs-kmods runs depmod and rebuild-initramfs only when kmods match
# the active kernel.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,from=kmods,source=/zfs/alma,target=/tmp/kmods \
    just -f /tmp/build.justfile install-zfs-kmods "/tmp/kmods/${TARGETARCH}" "Alma ${TARGETARCH}" && \
    just -f /tmp/build.justfile install-cockpit zfs && \
    just -f /tmp/build.justfile cleanup-dnf

# --- sshd host-key SELinux policy -------------------------------------------
# The image keeps host keys at /var/lib/sshd (persistent /var), which the stock
# targeted policy does not label. Compile and install the context-only module
# so /var/lib/sshd is labelled etc_t and generated keys transition to sshd_key_t.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,source=build/selinux/sshd,target=/tmp/sshd-selinux \
    just -f /tmp/build.justfile install-selinux-module /tmp/sshd-selinux sshd /var/lib/sshd

# --- Local rootfs overlays (late for optimal layer caching) -----------------
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /

# --- Final configuration, factory /etc snapshot, and bootc lint -------------
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    chmod +x /usr/sbin/setup-podman-user && \
    systemctl enable tailscaled podman.socket etc-overlay-sync.service && \
    just -f /tmp/build.justfile snapshot-factory-etc && \
    bootc container lint

ENTRYPOINT [ "/sbin/init" ]