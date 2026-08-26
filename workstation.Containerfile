FROM ghcr.io/ublue-os/bazzite:stable-44 AS base

COPY repos/ /etc/yum.repos.d/
RUN rm -rv /etc/yum.repos.d/wazuh.repo /etc/yum.repos.d/crowdsec.repo

COPY build/justfile /tmp/

FROM ghcr.io/braccae/kmods:latest AS kmods

FROM base AS final
LABEL containers.bootc 1

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh
# RUN /usr/bin/uv pip install --system packaging

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

RUN mkdir /var/roothome && \
    uv pip install --prefix=/usr \
    borgmatic && \
    rm -rfv /var/roothome

# SELinux utilities See: https://github.com/SELinuxProject/selinux/wiki/Tools
# RUN dnf install -y \
#     setroubleshoot-server \
#     policycoreutils \
#     policycoreutils-python-utils \
#     policycoreutils-restorecond \
#     selinuxconlist \
#     selinuxdefcon \
#     && dnf clean all

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

WORKDIR /tmp/zfs
RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit

RUN systemctl enable tailscaled

RUN export BOOTC_KERNEL_VERSION=$(just -f /tmp/justfile get-active-kernel) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

RUN mkdir -p /var/lib/alternatives && \
    just install-ublue-repos

WORKDIR /tmp

RUN just install-java && \
    just install-misc-tools && \
    just install-virt-tools

RUN just install-dev-mode

RUN rm -rv /opt && mkdir /opt

RUN just install-game-mode

RUN just install-kde-utils

# COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /
COPY rootfs/workstation/ /

# -------------------------------------------------------------
# SELINUX DIAGNOSTIC AND DEBUG STEP
# -------------------------------------------------------------
RUN dnf install -y policycoreutils && \
    echo "==================== [1] LOCATING SETFILES & POLICY ====================" && \
    which setfiles || find / -name setfiles 2>/dev/null && \
    LATEST_POLICY=$(ls -1 /etc/selinux/targeted/policy/policy.* 2>/dev/null | tail -n1) && \
    echo "Active Policy: ${LATEST_POLICY}" && \
    \
    echo "==================== [2] ACTIVE SELINUX MODULES ====================" && \
    semodule -l || true && \
    echo "--- Active Modules in store ---" && \
    find /var/lib/selinux/ /etc/selinux/ -name "*.cil" -o -name "*.pp" 2>/dev/null || true && \
    \
    echo "==================== [3] CHECKING LOCAL FILE CONTEXTS ====================" && \
    find /etc/selinux /var/lib/selinux -name "file_contexts.local*" -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null || true && \
    \
    echo "==================== [4] RUNNING SETFILES VALIDATION ====================" && \
    if [ -f "${LATEST_POLICY}" ]; then \
        echo "Validating /etc/selinux/targeted/contexts/files/file_contexts ..."; \
        setfiles -v -v -c "${LATEST_POLICY}" /etc/selinux/targeted/contexts/files/file_contexts || true; \
        if [ -f /var/lib/selinux/targeted/active/contexts/files/file_contexts ]; then \
            echo "Validating /var/lib/selinux active file_contexts ..."; \
            setfiles -v -v -c "${LATEST_POLICY}" /var/lib/selinux/targeted/active/contexts/files/file_contexts || true; \
        fi; \
    fi && \
    \
    echo "==================== [5] VERBOSE SEMODULE REBUILD ====================" && \
    semodule -v -v -v -B || true && \
    echo "==================== END SELINUX DIAGNOSTICS ===================="


RUN ostree container commit
RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]