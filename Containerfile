FROM quay.io/fedora/fedora-bootc:41

RUN dnf install -y \
    qemu-guest-agent \
    tailscale \
    cockpit-bridge \
    fuse \
    rclone \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

RUN systemctl enable qemu-guest-agent \
    && systemctl enable tailscaled

#RUN bootc container lint