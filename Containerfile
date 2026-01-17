FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base



RUN export EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" && \
    export RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" && \
    export RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm" && \
    export OPENZFS_REPO_URL="https://zfsonlinux.org/epel/zfs-release-3-0$(rpm --eval "%{dist}").noarch.rpm" && \
    dnf install -y --nogpgcheck \
    $EPEL_URL $RPMFUSION_FREE_URL $RPMFUSION_NONFREE_URL 
    # $OPENZFS_REPO_URL

# RUN dnf config-manager -y --disable zfs \
#     && dnf -y config-manager --enable zfs-kmod

ADD https://pkgs.tailscale.com/stable/rhel/10/tailscale.repo /etc/yum.repos.d/
COPY repos/*.repo /etc/yum.repos.d/


RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh

# FROM docker.io/debian:13-slim AS proxmox-backup-client-getter

# COPY --chmod=644 repos/proxmox.sources /etc/apt/sources.list.d/proxmox.sources
# ADD --chmod=644 https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg /usr/share/keyrings/proxmox-archive-keyring.gpg

# RUN apt update && apt install -y proxmox-backup-client-static

FROM base AS borgmatic-builder

RUN dnf install -y gcc python3-devel && \
    mkdir /var/roothome && \
    uv pip install --prefix=/tmp/borgmatic borgmatic

FROM base AS final
LABEL containers.bootc 1

RUN dnf install -y \
    qemu-guest-agent \
    container-selinux \
    just \
    zsh \
    tuned \
    realmd \
    sssd \
    tailscale \
    borgbackup \
    firewalld \
    sqlite \
    fuse \
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
    python3-pip \
    git \
    tmux \
    unzip \
    samba \
    samba-common-tools \
    samba-usershares \
    samba-client \
    samba-common-tools \
    cifs-utils \
    && dnf clean all

# RUN mkdir /var/roothome && \
#     uv pip install --prefix=/usr \
#     borgmatic && \
#     rm -rfv /var/roothome
COPY --from=borgmatic-builder /tmp/borgmatic /usr
# COPY --from=proxmox-backup-client-getter /usr/bin/proxmox-backup-client /usr/bin

RUN curl https://rclone.org/install.sh | bash

RUN dnf install -y \
    # bees \
    btrfs-progs\
    && dnf clean all

# SELinux utilities See: https://github.com/SELinuxProject/selinux/wiki/Tools
RUN dnf install -y \
    setroubleshoot-server \
    policycoreutils \
    policycoreutils-python-utils \
    policycoreutils-restorecond \
    libselinux-utils \
    && dnf clean all

RUN dnf -y reinstall selinux-policy-targeted policycoreutils policycoreutils-python-utils \
    && dnf clean all

COPY build/scripts /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh && \
    dnf install -y \
        crowdsec \
        crowdsec-firewall-bouncer-nftables\
    && dnf clean all

FROM base AS zfs-builder

ARG ZFS_VERSION=zfs-2.4.0

# Copy persistent MOK public key for secure boot
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der

COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh

FROM final

COPY --from=zfs-builder /tmp/zfs-rpms/ /tmp/rpms/
RUN dnf remove -y zfs-fuse && \
    ls /tmp/rpms/ && \
    dnf install -y /tmp/rpms/*.rpm && \
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
RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit \
    && curl https://raw.githubusercontent.com/45Drives/scripts/main/cockpit_font_fix/fix-cockpit.sh | bash

RUN export BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

# COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /

RUN systemctl enable tailscaled

RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]