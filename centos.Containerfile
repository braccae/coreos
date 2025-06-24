FROM quay.io/centos-bootc/centos-bootc:stream10

# RUN dnf install -y dnf-plugins

RUN dnf config-manager -y --add-repo https://pkgs.tailscale.com/stable/centos/10/tailscale.repo && \
    dnf config-manager -y --set-enabled crb && \
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm

RUN dnf install -y \
    qemu-guest-agent \
    btrfs-progs \
    tailscale \
    firewalld \
    sqlite \
    fuse \
    unzip \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf install -y \
    borgbackup \
    uv && \
    uv pip install --no-cache --system borgmatic

ADD https://rclone.org/install.sh /tmp/rclone.sh
RUN /bin/bash /tmp/rclone.sh

RUN dnf install -y \
    cockpit-bridge \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    cockpit-files && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf install -y \
    python3-psycopg2 \
    xdg-user-dirs \
    && dnf clean all \
    && rm -rf /var/*

COPY rootfs/common/ /
COPY rootfs/centos/ /

RUN systemctl enable qemu-guest-agent tailscaled

RUN bootc container lint