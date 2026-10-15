FROM ghcr.io/braccae/alma:latest AS base

FROM base AS final
RUN dnf install -y \
    podman \
    podman-docker \
    podman-compose \
    fuse-overlayfs \
    nix \
    && dnf clean all

COPY rootfs/dx/ /
RUN systemctl enable podman.socket nix-init.service

RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]