FROM ghcr.io/braccae/fedora:latest
LABEL containers.bootc 1

RUN dnf5 install -y --skip-unavailable \
    cockpit-machines \
    qemu-audio-dbuser \
    qemu-audio-spiceer \
    qemu-block-blkioer \
    qemu-block-curlr \
    qemu-block-iscsier \
    qemu-block-nfs \
    qemu-block-rbdriver \
    qemu-block-ssh \
    qemu-char-spice \
    qemu-common \
    qemu-device-display-qxl \
    qemu-device-display-vhost-user-gpu \
    qemu-device-display-virtio-gpu \
    qemu-device-display-virtio-gpu-ccw \
    qemu-device-display-virtio-gpu-gl \
    qemu-device-usb-host \
    qemu-device-usb-redirect \
    qemu-device-usb-smartcard \
    qemu-img \
    qemu-kvm \
    qemu-kvm-core \
    qemu-pr-helper \
    qemu-system-aarch64 \
    qemu-system-aarch64-core \
    qemu-system-arm \
    qemu-system-arm-core \
    qemu-system-riscv \
    qemu-system-riscv-core \
    qemu-system-x86 \
    qemu-system-x86-core \
    qemu-tools \
    qemu-ui-curses \
    qemu-ui-dbus \
    libvirt-daemon-driver-storage-zfs \
    libvirt-daemon-driver-storage \
    libvirt-daemon-driver-secret \
    libvirt-daemon-driver-lxc \
    libvirt-daemon-lxc \
    distrobox \
    && dnf5 clean all

WORKDIR /tmp/build/scripts

RUN dnf5 install -y \
    coreutils \
    attr \
    findutils \
    hostname \
    iproute \
    glibc-common \
    nfs-utils \
    libnfsidmap \
    sssd-nfs-idmap \
    NetworkManager-wifi \
    && dnf clean all

COPY build/scripts/* ./

# RUN bash get-latest-release.sh https://github.com/45Drives/cockpit-identities .rpm \
#     && bash get-latest-release.sh https://github.com/45Drives/cockpit-file-sharing .rpm el9 \
#     && mkdir /var/roothome \
#     && dnf install -y ./*.rpm \
#     && dnf clean all \
#     && rm -rfv /var/roothome

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

RUN systemctl enable tailscaled

RUN bootc container lint