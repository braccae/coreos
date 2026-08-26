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
# SETFILES INTERCEPTOR & SELINUX COMPILATION DEBUGGER
# -------------------------------------------------------------
RUN SETFILES_BIN=$(readlink -f $(which setfiles || echo /usr/sbin/setfiles)) && \
    echo "Found real setfiles at: ${SETFILES_BIN}" && \
    mv "${SETFILES_BIN}" "${SETFILES_BIN}.real" && \
    printf '#!/bin/bash\n\
LOG=/tmp/setfiles_debug.log\n\
echo "==================== [INTERCEPTED SETFILES CALL] ====================" | tee -a $LOG >&2\n\
echo "Arguments: $@" | tee -a $LOG >&2\n\
TMP_INPUT=$(mktemp)\n\
cat - > "${TMP_INPUT}"\n\
echo "Context definitions count: $(wc -l < ${TMP_INPUT})" | tee -a $LOG >&2\n\
echo "--- Running setfiles validation ---" | tee -a $LOG >&2\n\
"'%s.real'" -v -v $(echo "$@" | sed "s/-q//g") < "${TMP_INPUT}" 2>&1 | tee -a $LOG\n\
EXIT_CODE=${PIPESTATUS[0]}\n\
echo "Setfiles exited with code: ${EXIT_CODE}" | tee -a $LOG >&2\n\
echo "=====================================================================" | tee -a $LOG >&2\n\
exit ${EXIT_CODE}\n' "${SETFILES_BIN}" > "${SETFILES_BIN}" && \
    chmod +x "${SETFILES_BIN}" && \
    ln -sf "${SETFILES_BIN}" /usr/sbin/setfiles 2>/dev/null || true && \
    ln -sf "${SETFILES_BIN}" /usr/bin/setfiles 2>/dev/null || true && \
    ln -sf "${SETFILES_BIN}" /sbin/setfiles 2>/dev/null || true

RUN semodule -v -B || true

RUN cat /tmp/setfiles_debug.log 2>/dev/null || echo "No setfiles log recorded"

# Restore original setfiles binary
RUN SETFILES_BIN=$(readlink -f /usr/sbin/setfiles.real 2>/dev/null || echo /usr/sbin/setfiles.real) && \
    ORIG_BIN="${SETFILES_BIN%.real}" && \
    rm -f "${ORIG_BIN}" && \
    mv "${SETFILES_BIN}" "${ORIG_BIN}"


RUN ostree container commit
RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]