FROM ghcr.io/braccae/coreos:hci as base

COPY rootfs/workstation/ /
COPY build/justfile /tmp/

RUN dnf update -y \
    && dnf groupinstall -y --allowerasing "KDE Plasma Workspaces" \
    && systemctl set-default graphical.target

WORKDIR /tmp

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

RUN just install-ansible && \
    just install-java && \
    just install-misc-tools

RUN just install-kde-utils

RUN dnf remove -y \
    gnome-disk-utility

RUN ostree container commit