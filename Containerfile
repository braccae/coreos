FROM quay.io/fedora/fedora-bootc:42 AS builder

# Extract kernel version from container's embedded kernel
# https://bootc-dev.github.io/bootc/bootc-images.html#kernel
RUN KVER=$(ls /usr/lib/modules | head -1) && \
    echo "Target kernel version: $KVER" && \
    dnf install -y \
        gcc \
        make \
        autoconf \
        automake \
        libtool \
        git \
        "kernel-devel-$KVER" \
        libblkid-devel \
        libuuid-devel \
        libattr-devel \
        openssl-devel \
        zlib-devel \
        elfutils-libelf-devel \
        tree \
        fedora-packager \
        rpmdevtools \
        ncompress \
        libaio-devel \
        libffi-devel \
        libtirpc-devel \
        libudev-devel \
        python3-devel

# Build OpenZFS
RUN git clone --branch=zfs-2.3.3 https://github.com/openzfs/zfs.git /zfs && \
    cd /zfs && \
    ./autogen.sh && \
    ./configure --prefix=/usr --enable-linux-builtin=no --with-config=kernel && \
    make -j$(nproc) && \
    make rpm topdir=/build

FROM quay.io/fedora/fedora-bootc:42

COPY --from=builder /zfs/*.rpm /tmp/rpms/
COPY --from=builder /lib/modules /lib/modules

RUN depmod "$(ls /usr/lib/modules | head -1)"

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

COPY scripts/build /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh

# Install the built ZFS RPMs
RUN find /tmp/rpms -name "*.rpm" -exec rpm -ivh {} \;

COPY rootfs/btrfs_config/ /
COPY rootfs/common/ /

RUN systemctl enable tailscaled

RUN bootc container lint