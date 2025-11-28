FROM ghcr.io/braccae/coreos:fedora-hci as base

FROM base AS final

RUN dnf --version

COPY rootfs/workstation/ /
COPY build/justfile /tmp/

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

# RUN dnf install -y \
#     plasma-desktop \
#     plasma-workspace \
#     plasma-workspace-wayland \
#     plasma-settings \
#     sddm-wayland-plasma \
#     kde-baseapps \
#     kscreen sddm \
#     startplasma-wayland \
#     && systemctl set-default graphical.target

RUN dnf install -y \
    @kde-desktop-environment \
    && systemctl set-default graphical.target

WORKDIR /tmp

RUN just install-java && \
    just install-misc-tools

RUN just install-kde-utils

# RUN dnf remove -y \
#     gnome-disk-utility

RUN ostree container commit