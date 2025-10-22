FROM ghcr.io/ublue-os/bazzite-dx

COPY rootfs/workstation/ /
COPY build/justfile /tmp/

WORKDIR /tmp

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

RUN just install-ansible && \
    just install-java && \
    just install-misc-tools

RUN just install-kde-utils

RUN ostree container commit