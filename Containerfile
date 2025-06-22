FROM quay.io/fedora/fedora-bootc:42

RUN dnf5 install -y dnf5-plugins

RUN dnf5 config-manager addrepo \
    --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

RUN dnf5 install -y \
    qemu-guest-agent \
    tailscale \
    firewalld \
    sqlite \
    borgmatic \
    fuse \
    rclone \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf5 install -y \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    cockpit-files && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf5 install -y \
    python3-psycopg2 \
    && dnf clean all \
    && rm -rf /var/*

COPY rootfs/common/ /

RUN systemctl enable qemu-guest-agent tailscaled

RUN dnf5 downgrade -y \
    podman-5:5.5.0-1.fc42 \
    && dnf clean all \
    && rm -rf /var/*

RUN bootc container lint