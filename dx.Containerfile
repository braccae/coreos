FROM ghcr.io/braccae/alma:latest AS base

FROM base AS final

# Nix ships only in the dx image. The EPEL repository providing the nix RPMs is
# inherited from the base image.
RUN dnf install -y \
    podman \
    podman-docker \
    podman-compose \
    fuse-overlayfs \
    nix \
    checkpolicy \
    make \
    && dnf clean all

# dx-only overlay: nix.mount, /etc/nix/nix.conf and the /nix + /var/lib/nix
# tmpfiles entries. No unit is enabled by this overlay.
COPY rootfs/dx/ /

# --- Nix persistence -------------------------------------------------------
# /nix sits on the read-only composefs deployment root, so the store would be
# lost on every image update. Seed the persistent backing directory
# /var/lib/nix from the freshly installed /nix; `just setup-nix` merges the
# deployment's store into it and then bind-mounts it over /nix.
RUN mkdir -p /var/lib/nix && cp -a /nix/. /var/lib/nix/

# --- Nix SELinux policy ----------------------------------------------------
# The EPEL nix RPM ships no SELinux policy; without it nix-daemon trips AVCs
# under enforcing. Build the context-only module in build/selinux/nix/ and bake
# it into the image policy store. ostree relabels on deploy using these
# contexts. The module is inert until `just setup-nix` starts the daemon.
COPY build/selinux/nix /tmp/nix-selinux
RUN make -C /tmp/nix-selinux && \
    mkdir -p /usr/share/selinux/packages && \
    cp /tmp/nix-selinux/nix.pp /usr/share/selinux/packages/ && \
    semodule -i /tmp/nix-selinux/nix.pp && \
    (restorecon -RF /nix /var/lib/nix || true) && \
    rm -rf /tmp/nix-selinux && \
    dnf clean all

# Deliberately NOT enabled here: nix.mount and nix-daemon.socket stay disabled
# so Nix is never on automatically. An operator opts in with `just setup-nix`.
RUN systemctl enable podman.socket

# --- Factory /etc snapshot refresh ------------------------------------------
# The base image captured /usr/share/factory/etc before dx installed Nix, and
# etc-overlay-sync.service restores that snapshot over /etc in container mode.
# Without a refresh it would wipe the nixbld users/groups, /etc/nix/nix.conf and
# the podman.socket enablement, breaking Nix (and podman) in every container.
# Keep the runtime-owned removals in sync with the base Containerfile.
RUN rm -rf /usr/share/factory/etc && mkdir -p /usr/share/factory/etc && \
    cp -a /etc/. /usr/share/factory/etc/ && \
    rm -f /usr/share/factory/etc/machine-id \
          /usr/share/factory/etc/machine-info \
          /usr/share/factory/etc/hostname \
          /usr/share/factory/etc/resolv.conf

RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]
