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
# SEFCONTEXT_COMPILE INTERCEPTOR & REGEX VALIDATOR
# -------------------------------------------------------------
RUN SEF_BIN=$(readlink -f $(which sefcontext_compile 2>/dev/null || echo /usr/sbin/sefcontext_compile)) && \
    echo "Found sefcontext_compile at: ${SEF_BIN}" && \
    mv "${SEF_BIN}" "${SEF_BIN}.real" && \
    printf '#!/bin/bash\n\
echo "==================== [INTERCEPTED SEFCONTEXT_COMPILE CALL] ====================" >&2\n\
echo "Target file to compile: $@" >&2\n\
"'%s.real'" "$@" 2>&1\n\
EXIT_CODE=$?\n\
echo "sefcontext_compile exited with code: ${EXIT_CODE}" >&2\n\
if [ ${EXIT_CODE} -ne 0 ]; then\n\
    echo ">>> Scanning for invalid regex in $@ ... " >&2\n\
    python3 -c '\''\n\
import sys, re\n\
target = sys.argv[1]\n\
with open(target, "r", errors="replace") as f:\n\
    for idx, line in enumerate(f, 1):\n\
        line = line.strip()\n\
        if not line or line.startswith("#"):\n\
            continue\n\
        parts = line.split()\n\
        regex = parts[0]\n\
        try:\n\
            re.compile(regex)\n\
        except Exception as e:\n\
            print(f"FAILED REGEX AT LINE {idx}: {line} | ERROR: {e}", file=sys.stderr)\n\
'\'' "$1" 2>&1 >&2\n\
fi\n\
echo "===============================================================================" >&2\n\
exit ${EXIT_CODE}\n' "${SEF_BIN}" > "${SEF_BIN}" && \
    chmod +x "${SEF_BIN}" && \
    ln -sf "${SEF_BIN}" /usr/sbin/sefcontext_compile 2>/dev/null || true && \
    ln -sf "${SEF_BIN}" /usr/bin/sefcontext_compile 2>/dev/null || true && \
    ln -sf "${SEF_BIN}" /sbin/sefcontext_compile 2>/dev/null || true

RUN semodule -v -B || true

# Restore original sefcontext_compile binary
RUN SEF_BIN=$(readlink -f $(which sefcontext_compile 2>/dev/null || echo /usr/sbin/sefcontext_compile)) && \
    if [ -f "${SEF_BIN}.real" ]; then \
        rm -f "${SEF_BIN}" && \
        mv "${SEF_BIN}.real" "${SEF_BIN}"; \
    fi


RUN ostree container commit
RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]