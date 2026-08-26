FROM ghcr.io/ublue-os/bazzite:stable-44 AS base

COPY repos/ /etc/yum.repos.d/
RUN rm -rv /etc/yum.repos.d/wazuh.repo /etc/yum.repos.d/crowdsec.repo

COPY build/justfile /tmp/

FROM ghcr.io/braccae/kmods:latest AS kmods

FROM base AS final
LABEL containers.bootc 1

RUN dnf5 install -y \
    qemu-guest-agent \
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
    bees \
    python3-pip \
    git \
    tmux \
    samba \
    samba-common-tools \
    samba-usershares \
    && dnf clean all

COPY build/scripts /tmp/build_scripts
# RUN bash /tmp/build_scripts/wazuh-agent.sh

ARG TARGETARCH
COPY --from=kmods /zfs/bazzite/${TARGETARCH}/ /tmp/rpms/
RUN if [ -f /tmp/rpms/kernel-version.txt ]; then \
        KMOD_KERNEL=$(cat /tmp/rpms/kernel-version.txt) && \
        echo "kmods built for kernel: ${KMOD_KERNEL}" && \
        CURRENT_KERNEL=$(just -f /tmp/justfile get-active-kernel) && \
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
        echo "WARNING: No ZFS kernel modules found in the kmods image for Workstation ${TARGETARCH}. Skipping ZFS installation."; \
    fi && \
    dnf clean all

RUN export BOOTC_KERNEL_VERSION=$(just -f /tmp/justfile get-active-kernel) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

WORKDIR /tmp

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

RUN just install-java && \
    just install-misc-tools

RUN just install-dev-mode

# RUN just install-game-mode

RUN just install-kde-utils

# COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /
COPY rootfs/workstation/ /

RUN systemctl enable tailscaled

RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]