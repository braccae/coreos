FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base



RUN export EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" && \
    export RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" && \
    export RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm" && \
    export OPENZFS_REPO_URL="https://zfsonlinux.org/epel/zfs-release-2-8$(rpm --eval "%{dist}").noarch.rpm" && \
    dnf install -y --nogpgcheck \
    $EPEL_URL $RPMFUSION_FREE_URL $RPMFUSION_NONFREE_URL 
    # $OPENZFS_REPO_URL

# RUN dnf config-manager -y --disable zfs \
#     && dnf -y config-manager --enable zfs-kmod

ADD https://pkgs.tailscale.com/stable/rhel/10/tailscale.repo /etc/yum.repos.d/
COPY repos/*.repo /etc/yum.repos.d/

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh

FROM base AS zfs-builder

ARG ZFS_VERSION=zfs-2.4.0-rc3

# Copy persistent MOK public key for secure boot
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der

COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh

FROM base AS libvirt-builder

RUN dnf install -y \
    wget \
    rpm-build \
    libvirt-devel \
    gcc \
    meson \
    ninja-build \
    libxml2-devel \
    gnutls-devel \
    pciutils-devel \
    procps-ng-devel \
    libselinux-devel \
    libtool \
    dtrace \
    qemu-img \
    audit-libs-devel \
    augeas \
    cyrus-sasl-devel \
    device-mapper-devel \
    firewalld-filesystem \
    gettext \
    git \
    glib2-devel \
    iscsi-initiator-utils \
    json-c-devel \
    libacl-devel \
    libattr-devel \
    libblkid-devel \
    libcap-ng-devel \
    libcurl-devel \
    libnl3-devel \
    libpcap-devel \
    librdmacm-devel \
    libseccomp-devel \
    libtirpc-devel \
    libuuid-devel \
    libvirt-client \
    libxslt-devel \
    lvm2-devel \
    numactl-devel \
    openldap-devel \
    parted-devel \
    python3-devel \
    readline-devel \
    rpcgen \
    sanlock-devel \
    systemd-devel \
    wget \
    xfsprogs-devel \
    libnbd-devel \
    libpciaccess-devel \
    librados-devel \
    librbd-devel \
    numad \
    python3-docutils \
    python3-pytest \
    systemtap-sdt-devel \
    wireshark-devel

COPY --from=zfs-builder /tmp/zfs-dev-rpms/*.rpm /tmp/zfs-dev-rpms/

RUN dnf install -y \
    /tmp/zfs-dev-rpms/*.rpm

# Build libvirt with ZFS driver using dedicated script
COPY build/scripts/build-libvirt-zfs.sh /tmp/build-libvirt-zfs.sh
RUN bash /tmp/build-libvirt-zfs.sh

FROM base AS final
LABEL containers.bootc 1

RUN dnf install -y \
    qemu-guest-agent \
    container-selinux \
    just \
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
    && dnf clean all

RUN mkdir /var/roothome && \
    uv pip install --prefix=/usr \
    borgmatic==2.0.8 && \
    rm -rfv /var/roothome

RUN curl https://rclone.org/install.sh | bash

RUN dnf install -y \
    # bees \
    btrfs-progs

# SELinux utilities See: https://github.com/SELinuxProject/selinux/wiki/Tools
RUN dnf install -y \
    setroubleshoot-server \
    policycoreutils \
    policycoreutils-python-utils \
    policycoreutils-restorecond \
    libselinux-utils \
    && dnf clean all

COPY build/scripts /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh && \
    dnf install -y \
        crowdsec \
        crowdsec-firewall-bouncer-nftables

COPY --from=zfs-builder /tmp/zfs-rpms/ /tmp/zfs-rpms/
COPY --from=libvirt-builder /tmp/libvirt-rpms/ /tmp/libvirt-rpms/
RUN dnf remove -y zfs-fuse && \
    ls /tmp/zfs-rpms/ /tmp/libvirt-rpms/ && \
    dnf install -y /tmp/zfs-rpms/*.rpm /tmp/libvirt-rpms/*.rpm && \
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
