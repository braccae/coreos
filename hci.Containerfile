FROM ghcr.io/braccae/coreos:sha-1a944db


RUN dnf5 install -y --skip-unavailable \
    cockpit-machines \
    qemu-audio-dbuser \
    qemu-audio-pipewireriver \
    qemu-audio-spiceer \
    qemu-block-blkioer \
    qemu-block-curlr \
    qemu-block-dmg \
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
    qemu-device-display-virtio-gpu-pci \
    qemu-device-display-virtio-gpu-pci-gl \
    qemu-device-display-virtio-gpu-pci-rutabaga \
    qemu-device-display-virtio-gpu-rutabaga \
    qemu-device-display-virtio-vga \
    qemu-device-display-virtio-vga-gl \
    qemu-device-display-virtio-vga-rutabaga \
    qemu-device-usb-host \
    qemu-device-usb-redirect \
    qemu-device-usb-smartcard \
    qemu-docs \
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
    qemu-ui-egl-headless \
    qemu-ui-gtk \
    qemu-ui-opengl \
    qemu-ui-sdl \
    qemu-ui-spice-app \
    qemu-ui-spice-core \
    qemu-user \
    qemu-user-binfmt \
    qemu-user-static \
    qemu-user-static-aarch64 \
    qemu-user-static-arm \
    qemu-user-static-riscv \
    cockpit-ws-selinux \
    distrobox \
    && dnf5 clean all


# RUN dnf5 install -y https://zfsonlinux.org/fedora/zfs-release-2-8$(rpm --eval "%{dist}").noarch.rpm \
#     && dnf5 clean all
# RUN KERNEL_VERSION=$(uname -r | awk -F'-' '{print $1}') && \
#     dnf5 install -y kernel-devel-$KERNEL_VERSION && \
#     dnf5 install -y zfs && \
#     rm -rf /usr/src/zfs_$KERNEL_VERSION && \
#     rm -rf /usr/lib/modules/$KERNEL_VERSION/build \
#     && dnf5 clean all

# WORKDIR /tmp
# RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit
RUN sudo dnf5 install -y https://github.com/45Drives/cockpit-file-sharing/releases/download/v4.2.10/cockpit-file-sharing-4.2.10-1.el8.noarch.rpm \
    && dnf5 clean all

RUN dnf install -y https://github.com/k3s-io/k3s-selinux/releases/download/v1.6.latest.1/k3s-selinux-1.6-1.coreos.noarch.rpm && \
        curl -sfL https://get.k3s.io | \
        INSTALL_K3S_SKIP_ENABLE=true \
        INSTALL_K3S_SKIP_START=true \
        sh -

COPY rootfs/hci/ /

RUN systemctl enable tailscaled

RUN bootc container lint
