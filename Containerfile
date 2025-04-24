FROM quay.io/fedora/fedora-bootc:42

RUN dnf install -y \
    qemu-guest-agent \
    tailscale \
    borgmatic \
    fuse \
    rclone \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf install -y \
    cockpit-ws \
    cockpit-bridge \
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