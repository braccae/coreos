FROM quay.io/fedora/fedora-bootc:41

RUN dnf install -y \
    qemu-guest-agent \
    tailscale \
    cockpit-bridge \
    borgmatic \
    fuse \
    rclone \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

COPY rootfs/* /
#COPY rootfs/etc/containers/storage.conf /etc/containers/storage.conf.tmp

RUN systemctl enable qemu-guest-agent tailscaled

RUN bootc container lint