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


RUN bootc container lint