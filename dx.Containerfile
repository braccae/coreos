FROM ghcr.io/braccae/alma:latest
LABEL containers.bootc 1

# --- Nix package & persistent /var/lib/nix store seed -----------------------
# Nix ships only in the dx image (EPEL repository is inherited from base).
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-nix && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Nix SELinux policy -----------------------------------------------------
# The EPEL nix RPM ships no SELinux policy; compile and install the context-only
# module in build/selinux/nix/ via read-only bind mount so nothing leaks into
# the image layers.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    --mount=type=bind,source=build/selinux/nix,target=/tmp/nix-selinux \
    just -f /tmp/build.justfile install-selinux-module /tmp/nix-selinux nix /nix /var/lib/nix

# --- Local rootfs overlay (late for optimal layer caching) ------------------
# dx-only overlay: nix.mount, /etc/nix/nix.conf, and /nix + /var/lib/nix
# tmpfiles entries. No Nix unit is enabled by this overlay.
COPY rootfs/dx/ /

# --- Final configuration, factory /etc snapshot, and bootc lint -------------
# Deliberately NOT enabling nix.mount or nix-daemon.socket: operators opt in
# with `just setup-nix`. Refresh factory /etc so nixbld users/groups and
# /etc/nix/nix.conf survive container-mode boot.
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    systemctl enable podman.socket && \
    just -f /tmp/build.justfile snapshot-factory-etc && \
    bootc container lint

ENTRYPOINT [ "/sbin/init" ]
