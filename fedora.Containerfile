ARG KMODS_IMAGE=localhost/kmods:latest
FROM quay.io/fedora/fedora-bootc:43 AS base

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh

RUN dnf5 install -y dnf5-plugins \
    && dnf clean all

RUN dnf5 config-manager addrepo \
    --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo

FROM base AS borgmatic-builder

RUN dnf install -y gcc python3-devel && \
    mkdir /var/roothome && \
    uv pip install --prefix=/tmp/borgmatic borgmatic

FROM base AS final
LABEL containers.bootc 1

RUN dnf5 install -y \
    qemu-guest-agent \
    container-selinux \
    just \
    zsh \
    tuned \
    realmd \
    sssd \
    tailscale \
    firewalld \
    sqlite \
    borgbackup \
    fuse \
    rclone \
    rsync \
    cockpit-system \
    cockpit-bridge \
    cockpit-networkmanager \
    cockpit-podman \
    cockpit-ostree \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-files \
    python3-psycopg2 \
    python3-pcp \
    xdg-user-dirs \
    bees \
    python3-pip \
    git \
    tmux \
    samba \
    samba-common-tools \
    samba-usershares \
    samba-client \
    samba-common-tools \
    cifs-utils \
    && dnf clean all

COPY --from=borgmatic-builder /tmp/borgmatic /usr

# SELinux utilities See: https://github.com/SELinuxProject/selinux/wiki/Tools
RUN dnf install -y \
    setroubleshoot-server \
    policycoreutils \
    policycoreutils-python-utils \
    policycoreutils-restorecond \
    selinuxconlist \
    selinuxdefcon \
    && dnf clean all

COPY build/scripts /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh

FROM ${KMODS_IMAGE} AS kmods

FROM final

ARG TARGETARCH
COPY --from=kmods /zfs/fedora/${TARGETARCH}/ /tmp/rpms/
RUN if [ -f /tmp/rpms/kernel-version.txt ]; then \
        KMOD_KERNEL=$(cat /tmp/rpms/kernel-version.txt) && \
        echo "kmods built for kernel: ${KMOD_KERNEL}" && \
        CURRENT_KERNEL=$(basename /lib/modules/*) && \
        echo "Current base kernel: ${CURRENT_KERNEL}" && \
        if [ "$CURRENT_KERNEL" = "$KMOD_KERNEL" ]; then \
            dnf5 remove -y zfs-fuse && \
            dnf5 install -y /tmp/rpms/*.rpm && \
            echo "Correcting ZFS kernel module dependencies..." && \
            depmod -a \
            --filesyms /usr/lib/modules/${CURRENT_KERNEL}/System.map \
            ${CURRENT_KERNEL} && \
            echo "✓ ZFS modules installed and depmod completed successfully for kernel ${CURRENT_KERNEL}"; \
        else \
            echo "WARNING: Kernel version mismatch! (Current: ${CURRENT_KERNEL}, Kmods: ${KMOD_KERNEL}). Skipping ZFS installation."; \
        fi; \
    else \
        echo "WARNING: No ZFS kernel modules found in the kmods image for Fedora ${TARGETARCH}. Skipping ZFS installation."; \
    fi && \
    dnf clean all

WORKDIR /tmp/zfs
RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit

RUN export BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

    # COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /
RUN chmod +x /usr/sbin/setup-podman-user

RUN systemctl enable tailscaled

# RUN sed -i 's/enforcing=1/enforcing=0/g' /usr/lib/bootc/kargs.d/999-selinux.toml
RUN bootc container lint
ENTRYPOINT [ "/sbin/init" ]