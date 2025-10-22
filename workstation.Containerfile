FROM ghcr.io/braccae/coreos:latest

COPY rootfs/workstation/ /
COPY build/justfile /tmp/

WORKDIR /tmp

RUN dnf install -y \
    just && \
    dnf clean all

RUN mkdir -p /var/lib/alternatives && \
    just add-repos && \
    dnf clean all

RUN just install-ansible && \
    just install-java && \
    just install-misc-tools && \
    dnf clean all

RUN just install-kde-plasma && \
    just install-kde-utils && \
    dnf clean all

RUN bootc container lint && \
    ostree container commit