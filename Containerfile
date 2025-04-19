FROM quay.io/fedora/fedora-bootc:42

RUN dnf install -y \
    qemu-guest-agent \
    cloud-init \
    tailscale \
    borgmatic \
    fuse \
    rclone \
    rsync && \
    dnf clean all && \
    rm -rf /var/*

RUN dnf install -y \
    cockpit-bridge \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    cockpit-files && \
    dnf clean all && \
    rm -rf /var/*

#RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

COPY rootfs/ /
#RUN chmod 0440 /etc/sudoers.d/10-core-group
#COPY rootfs/etc/containers/storage.conf /etc/containers/storage.conf.tmp

RUN systemctl enable qemu-guest-agent tailscaled

RUN bootc container lint