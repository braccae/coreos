FROM ghcr.io/braccae/coreos
LABEL containers.bootc 1


RUN dnf install -y  \
    cockpit-machines \
    qemu-kvm \
    qemu-img \
    qemu-kvm-core \
    qemu-kvm-common \
    qemu-kvm-audio-pa \
    qemu-kvm-block-blkio \
    qemu-kvm-block-curl \
    qemu-kvm-block-rbd \
    qemu-kvm-device-display-virtio-gpu \
    qemu-kvm-device-display-virtio-gpu-pci \
    qemu-kvm-device-usb-host \
    qemu-kvm-device-usb-redirect \
    qemu-kvm-ui-spice \
    qemu-kvm-tools \
    qemu-guest-agent \
    qemu-pr-helper \
    libvirt-daemon \
    libvirt-daemon-driver-qemu \
    libvirt-daemon-driver-interface \
    libvirt-daemon-driver-network \
    libvirt-daemon-driver-nodedev \
    libvirt-daemon-driver-nwfilter \
    libvirt-daemon-driver-secret \
    libvirt-daemon-driver-storage \
    libvirt-daemon-driver-storage-core \
    libvirt-daemon-driver-storage-disk \
    libvirt-daemon-driver-storage-iscsi \
    libvirt-daemon-driver-storage-logical \
    libvirt-daemon-driver-storage-mpath \
    libvirt-daemon-driver-storage-rbd \
    libvirt-daemon-driver-storage-scsi \
    libvirt-daemon-config-network \
    libvirt-daemon-config-nwfilter \
    libvirt-daemon-kvm \
    libvirt-client \
    libvirt-client-qemu \
    distrobox \
    && dnf clean all

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
    samba \
    samba-common-tools

COPY build/scripts/* ./

RUN bash get-latest-release.sh https://github.com/45Drives/cockpit-identities .rpm \
    && bash get-latest-release.sh https://github.com/45Drives/cockpit-file-sharing .rpm el9 noarch \
    && mkdir /var/roothome \
    && dnf install -y ./*.rpm \
    && dnf clean all \
    && rm -rv /var/roothome

# RUN dnf install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.6.latest.1/k3s-selinux-1.6-1.coreos.noarch.rpm && \
#         curl -sfL https://get.k3s.io | \
#         INSTALL_K3S_SKIP_ENABLE=true \
#         INSTALL_K3S_SKIP_START=true \
#         INSTALL_K3S_SKIP_SELINUX_RPM=true \
#         INSTALL_K3S_SELINUX_WARN=true \
#         INSTALL_K3S_BIN_DIR=/usr/bin \
#         sh -

# # RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh -o 
# ADD https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh /tmp/k3d_install.sh
# RUN K3D_INSTALL_DIR=/usr/bin bash /tmp/k3d_install.sh

COPY rootfs/hci/ /

RUN systemctl enable tailscaled selinux-recover

RUN bootc container lint
