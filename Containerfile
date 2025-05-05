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

COPY rootfs/ /

RUN systemctl enable qemu-guest-agent tailscaled

RUN bootc container lint