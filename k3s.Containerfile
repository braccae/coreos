FROM ghcr.io/braccae/alma:latest
LABEL containers.bootc 1

WORKDIR /tmp/build/scripts

RUN dnf install -y \
    coreutils \
    attr \
    findutils \
    hostname \
    iproute \
    glibc-common \
    systemd \
    nfs-utils \
    libnfsidmap \
    sssd-nfs-idmap \
    && dnf clean all

COPY build/scripts/* ./

RUN dnf install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.6.latest.1/k3s-selinux-1.6-1.coreos.noarch.rpm && \
        curl -sfL https://get.k3s.io | \
        INSTALL_K3S_SKIP_ENABLE=true \
        INSTALL_K3S_SKIP_START=true \
        INSTALL_K3S_SKIP_SELINUX_RPM=true \
        INSTALL_K3S_SELINUX_WARN=true \
        INSTALL_K3S_BIN_DIR=/usr/bin \
        sh -

# # RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh -o 
# ADD https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh /tmp/k3d_install.sh
# RUN K3D_INSTALL_DIR=/usr/bin bash /tmp/k3d_install.sh

RUN bootc container lint
