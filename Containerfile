FROM quay.io/fedora/fedora-bootc:42

RUN dnf5 install -y \
    qemu-guest-agent \
    tailscale \
    borgmatic \
    fuse \
    rclone \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf5 install -y \
    cockpit-bridge \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    cockpit-files && \
    dnf clean all && \
    rm -rf /var/*

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
    qemu-user-static-riscv


COPY rootfs/ /

RUN systemctl enable qemu-guest-agent tailscaled

RUN bootc container lint