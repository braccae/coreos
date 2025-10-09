FROM ghcr.io/braccae/coreos:latest as base

FROM base AS builder

RUN dnf install -y \
    git \
    gettext \
    nodejs \
    make

WORKDIR /tmp/build

RUN git clone https://github.com/cockpit-docker/cockpit-docker \
    && cd cockpit-docker \
    && NODE_ENV=production make rpm

RUN tree ./ && exit 1

# FROM base AS final

# RUN dnf5 config-manager addrepo \
#     --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo \
#     && dnf install -y \
#     docker-ce \
#     docker-ce-cli \
#     containerd.io \
#     docker-buildx-plugin \
#     docker-compose-plugin \
#     && systemctl enable docker