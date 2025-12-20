# FROM quay.io/fedora-ostree-desktops/kinoite:43 as base
FROM ghcr.io/ublue-os/bazzite:stable-43 as base

COPY repos/ /etc/yum.repos.d/
COPY build/justfile /tmp/

FROM base AS zfs-builder

ARG ZFS_VERSION=zfs-2.4.0

# Copy persistent MOK public key for secure boot
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der

# COPY --from=ghcr.io/ublue-os/akmods:coreos-stable-43 / /tmp/ublue/akmods

COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh

FROM base AS final
LABEL containers.bootc 1

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh
# RUN /usr/bin/uv pip install --system packaging

RUN dnf5 install -y \
    qemu-guest-agent \
    container-selinux \
    just \
    zsh \
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
    bees \
    python3-pip \
    git \
    tmux \
    samba \
    samba-common-tools \
    samba-usershares \
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
    KERNEL_VERSION=$(just -f /tmp/justfile get-active-kernel) && \
    echo "Found kernel version: ${KERNEL_VERSION}" && \
    depmod -a \
    --filesyms /usr/lib/modules/${KERNEL_VERSION}/System.map \
    ${KERNEL_VERSION} && \
    echo "✓ depmod completed successfully for kernel ${KERNEL_VERSION}" && \
    \
    dnf clean all

WORKDIR /tmp/zfs
RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit

RUN systemctl enable tailscaled

RUN export BOOTC_KERNEL_VERSION=$(just -f /tmp/justfile get-active-kernel) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

WORKDIR /tmp

RUN just install-java && \
    just install-misc-tools

RUN just install-dev-mode

RUN rm -rv /opt && mkdir /opt

RUN just install-game-mode

RUN just install-kde-utils

# COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /
COPY rootfs/workstation/ /

RUN rm -fv /etc/sudoers.d/100-passwordless-wheel /etc/polkit-1/rules.d/10-systemd-nopasswd.rules

RUN ostree container commit
RUN bootc container lint
