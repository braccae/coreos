FROM ghcr.io/braccae/coreos:latest as base

FROM base AS builder

RUN dnf install -y \
    git \
    gettext \
    nodejs \
    make \
    rpmbuild \
    libappstream-glib \
    libappstream-glib-devel

RUN rm -rv /root
WORKDIR /tmp/build

RUN git clone https://github.com/chabad360/cockpit-docker.git \
    && cd cockpit-docker \
    && NODE_ENV=production make rpm

FROM base AS final

RUN dnf remove -y moby-engine \
    && dnf5 config-manager addrepo \
    --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo \
    && dnf install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    && systemctl enable docker

RUN --mount=type=bind,from=builder,source=/tmp/build/cockpit-docker,target=/tmp/build/cockpit-docker \
    dnf remove -y \
    cockpit-podman \
    && dnf install -y --allowerasing /tmp/build/cockpit-docker/*.rpm