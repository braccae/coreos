FROM quay.io/fedora/fedora-bootc:42 AS zfs-builder

ARG ZFS_VERSION=zfs-2.4.0-rc3

# Copy persistent MOK public key for secure boot
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der

COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh

FROM quay.io/fedora/fedora-bootc:42
LABEL containers.bootc 1

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh
# RUN /usr/bin/uv pip install --system packaging

RUN dnf5 install -y dnf5-plugins \
    && dnf clean all

RUN dnf5 config-manager addrepo \
    --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

RUN dnf5 install -y \
    qemu-guest-agent \
    container-selinux \
    just \
    tuned \
    realmd \
    sssd \
    tailscale \
    firewalld \
    sqlite \
    borgbackup \
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
    python3-pcp \
    xdg-user-dirs \
    bees \
    python3-pip \
    git \
    tmux \
    && dnf clean all

RUN mkdir /var/roothome && \
    uv pip install --prefix=/usr \
    borgmatic==2.0.11 && \
    rm -rfv /var/roothome

# SELinux utilities See: https://github.com/SELinuxProject/selinux/wiki/Tools
RUN dnf install -y \
    setroubleshoot-server \
    policycoreutils \
    policycoreutils-python-utils \
    policycoreutils-restorecond \
    selinuxconlist \
    selinuxdefcon \
    && dnf clean all

COPY build/scripts /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh

COPY --from=zfs-builder /tmp/zfs-rpms/ /tmp/rpms/
RUN dnf5 remove -y zfs-fuse && \
    ls /tmp/rpms/ && \
    dnf5 install -y /tmp/rpms/*.rpm && \
    echo "Correcting ZFS kernel module dependencies..." && \
    KERNEL_VERSION=$(basename /lib/modules/*) && \
    echo "Found kernel version: ${KERNEL_VERSION}" && \
    depmod -a \
    --filesyms /usr/lib/modules/${KERNEL_VERSION}/System.map \
    ${KERNEL_VERSION} && \
    echo "✓ depmod completed successfully for kernel ${KERNEL_VERSION}" && \
    \
    dnf clean all

WORKDIR /tmp/zfs
RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit

# COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /

RUN systemctl enable tailscaled

RUN export BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

RUN bootc container lint