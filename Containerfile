FROM ghcr.io/ublue-os/ucore-hci:stable-zfs

RUN dnf5 install -y \
    qemu-guest-agent \
    git \
    tailscale \
    borgmatic \
    fuse \
    rclone \
    rsync \
    && dnf5 clean all

RUN dnf5 install -y \
    cockpit-bridge \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    cockpit-files \
    && dnf5 clean all
    
# WORKDIR /tmp
# RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit
RUN sudo dnf5 install -y https://github.com/45Drives/cockpit-file-sharing/releases/download/v4.2.10/cockpit-file-sharing-4.2.10-1.el8.noarch.rpm \
    && dnf5 clean all


COPY rootfs/ /

RUN systemctl enable tailscaled

RUN bootc container lint