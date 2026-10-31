FROM ghcr.io/braccae/alma:latest as base

FROM base AS builder

RUN dnf install -y \
    git \
    gettext \
    nodejs \
    make \
    libappstream-glib \
    libappstream-glib-devel \
    rpm-build

RUN rm -rv /root
WORKDIR /tmp/build

RUN git clone https://github.com/chabad360/cockpit-docker.git \
    && cd cockpit-docker \
    && NODE_ENV=production make rpm

FROM base AS final

# --allowerasing: the Alma base ships podman-docker, whose `docker` command
# conflicts with docker-ce. Let the transaction replace the shim with the real
# engine instead of failing the build.
RUN dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo \
    && dnf install -y --allowerasing \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    && systemctl enable docker

# COPY --from=builder /usr/local/share/cockpit/docker /usr/share/cockpit/docker

RUN --mount=type=bind,from=builder,source=/tmp/build/cockpit-docker,target=/tmp/build/cockpit-docker \
    rpm -i --nodeps \
    /tmp/build/cockpit-docker/*.rpm