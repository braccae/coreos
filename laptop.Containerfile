FROM ghcr.io/braccae/coreos:latest

COPY rootfs/workstation/ /
COPY build/justfile /tmp/

WORKDIR /tmp

RUN dnf install -y \
    just && \
    dnf clean all

RUN mkdir -p /var/lib/alternatives && \
    just add-repos

RUN just install-ansible && \
    just install-java && \
    just install-misc-tools

RUN just install-cosmic-desktop

RUN just install-linux-surface

RUN ostree container commit