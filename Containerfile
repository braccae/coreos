FROM quay.io/fedora/fedora-bootc:42 AS zfs-builder

ARG ZFS_VERSION="2.3.4"

COPY build/scripts/zfs.sh /tmp/build_scripts/zfs.sh
RUN bash /tmp/build_scripts/zfs.sh

FROM quay.io/fedora/fedora-bootc:42
LABEL containers.bootc 1

RUN dnf5 install -y dnf5-plugins \
    && dnf clean all

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
    xdg-user-dirs \
    python3-pip \
    && dnf clean all

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh
# RUN /usr/bin/uv pip install --system packaging

COPY build/scripts /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh


COPY --from=zfs-builder /build/RPMS/install/*.rpm /tmp/rpms/
RUN dnf5 remove -y zfs-fuse && \
    ls /tmp/rpms/ && \
    dnf5 install -y /tmp/rpms/*.rpm && dnf clean all

COPY rootfs/btrfs_config/ /
COPY rootfs/common/ /

RUN systemctl enable tailscaled selinux-recover

RUN bootc container lint
