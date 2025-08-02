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
    rsync \
    cockpit-system \
    cockpit-bridge \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-files \
    python3-psycopg2 \
    container-selinux \
    xdg-user-dirs \
    && dnf clean all

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh && \
    /usr/bin/uv pip install --system packaging

COPY rootfs/btrfs_config/ /
COPY rootfs/common/ /

RUN systemctl enable qemu-guest-agent tailscaled

RUN bootc container lint