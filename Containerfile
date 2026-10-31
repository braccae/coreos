ARG KMODS_IMAGE=localhost/kmods:latest
FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base



RUN export EPEL_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" && \
    export RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm" && \
    export RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm" && \
    export OPENZFS_REPO_URL="https://zfsonlinux.org/epel/zfs-release-3-0$(rpm --eval "%{dist}").noarch.rpm" && \
    dnf install -y --nogpgcheck \
    $EPEL_URL $RPMFUSION_FREE_URL $RPMFUSION_NONFREE_URL 
    # $OPENZFS_REPO_URL

# RUN dnf config-manager -y --disable zfs \
#     && dnf -y config-manager --enable zfs-kmod

ADD https://pkgs.tailscale.com/stable/rhel/10/tailscale.repo /etc/yum.repos.d/
COPY repos/*.repo /etc/yum.repos.d/


RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_UNMANAGED_INSTALL="/usr/bin" sh

# FROM docker.io/debian:13-slim AS proxmox-backup-client-getter

# COPY --chmod=644 repos/proxmox.sources /etc/apt/sources.list.d/proxmox.sources
# ADD --chmod=644 https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg /usr/share/keyrings/proxmox-archive-keyring.gpg

# RUN apt update && apt install -y proxmox-backup-client-static

FROM base AS final
LABEL containers.bootc 1

RUN dnf install -y \
    qemu-guest-agent \
    container-selinux \
    just \
    zsh \
    tuned \
    realmd \
    sssd \
    tailscale \
    borgbackup \
    restic \
    firewalld \
    sqlite \
    fuse \
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
    python3-pip \
    git \
    tmux \
    unzip \
    samba \
    samba-common-tools \
    samba-usershares \
    samba-client \
    samba-common-tools \
    cifs-utils \
    nodejs \
    nodejs-full-i18n \
    nodejs-npm \
    && dnf clean all

# COPY --from=proxmox-backup-client-getter /usr/bin/proxmox-backup-client /usr/bin

RUN curl https://rclone.org/install.sh | bash

RUN dnf install -y \
    # bees \
    btrfs-progs\
    && dnf clean all

# SELinux utilities See: https://github.com/SELinuxProject/selinux/wiki/Tools
RUN dnf install -y \
    setroubleshoot-server \
    policycoreutils \
    policycoreutils-python-utils \
    policycoreutils-restorecond \
    libselinux-utils \
    && dnf clean all

RUN dnf -y reinstall selinux-policy-targeted policycoreutils policycoreutils-python-utils \
    && dnf clean all

COPY build/scripts /tmp/build_scripts
RUN bash /tmp/build_scripts/wazuh-agent.sh && \
    dnf install -y \
        crowdsec \
        crowdsec-firewall-bouncer-nftables\
    && dnf clean all

FROM ${KMODS_IMAGE} AS kmods

FROM final

ARG TARGETARCH
COPY --from=kmods /zfs/alma/${TARGETARCH}/ /tmp/rpms/
RUN if [ -f /tmp/rpms/kernel-version.txt ]; then \
        KMOD_KERNEL=$(cat /tmp/rpms/kernel-version.txt) && \
        echo "kmods built for kernel: ${KMOD_KERNEL}" && \
        CURRENT_KERNEL=$(basename /lib/modules/*) && \
        echo "Current base kernel: ${CURRENT_KERNEL}" && \
        if [ "$CURRENT_KERNEL" = "$KMOD_KERNEL" ]; then \
            dnf remove -y zfs-fuse && \
            dnf install -y /tmp/rpms/*.rpm && \
            echo "Correcting ZFS kernel module dependencies..." && \
            depmod -a \
            --filesyms /usr/lib/modules/${CURRENT_KERNEL}/System.map \
            ${CURRENT_KERNEL} && \
            echo "✓ ZFS modules installed and depmod completed successfully for kernel ${CURRENT_KERNEL}"; \
        else \
            echo "WARNING: Kernel version mismatch! (Current: ${CURRENT_KERNEL}, Kmods: ${KMOD_KERNEL}). Skipping ZFS installation."; \
        fi; \
    else \
        echo "WARNING: No ZFS kernel modules found in the kmods image for Alma ${TARGETARCH}. Skipping ZFS installation."; \
    fi && \
    dnf clean all

WORKDIR /tmp/zfs
RUN git clone https://github.com/45drives/cockpit-zfs-manager.git && cp -r cockpit-zfs-manager/zfs /usr/share/cockpit \
    && curl https://raw.githubusercontent.com/45Drives/scripts/main/cockpit_font_fix/fix-cockpit.sh | bash

RUN export BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    cd /usr/lib/modules/$BOOTC_KERNEL_VERSION && \
    mkdir /var/roothome && \
    dracut -f --kver $BOOTC_KERNEL_VERSION $BOOTC_KERNEL_VERSION && \
    rm -rfv /var/roothome

# COPY rootfs/btrfs_config/ /
COPY rootfs/non_btrfs/ /
COPY rootfs/common/ /
RUN chmod +x /usr/sbin/setup-podman-user

RUN systemctl enable tailscaled podman.socket etc-overlay-sync.service

RUN dnf install -y \
    podman \
    podman-docker \
    podman-compose \
    fuse-overlayfs \
    && dnf clean all

# Nix is deliberately NOT part of the base image: it ships only in the dx
# variant (dx.Containerfile), installed with every unit disabled. See
# `just setup-nix` in rootfs/common/justfile.

# --- sshd host-key SELinux policy ------------------------------------------
# The image keeps host keys at /var/lib/sshd (persistent /var), which the stock
# targeted policy does not label. systemd-tmpfiles 'd' only mkdirs, so the dir
# inherited var_lib_t and ssh-keygen was denied write under enforcing, failing
# sshd.service at boot. Build the context-only module in build/selinux/sshd/
# so the directory is labelled etc_t (the only host-key dir type ssh_keygen_t
# may write to) and the generated keys type-transition to sshd_key_t, which
# sshd_t can read. The tmpfiles entry now uses type 'Z' to apply the context.
COPY build/selinux/sshd /tmp/sshd-selinux
RUN dnf install -y checkpolicy make && \
    make -C /tmp/sshd-selinux && \
    mkdir -p /usr/share/selinux/packages && \
    cp /tmp/sshd-selinux/sshd.pp /usr/share/selinux/packages/ && \
    semodule -i /tmp/sshd-selinux/sshd.pp && \
    (restorecon -RF /var/lib/sshd || true) && \
    rm -rf /tmp/sshd-selinux && \
    dnf clean all

# --- Hermes Agent CLI -------------------------------------------------------
# Ship the Hermes CLI in the base image so a deployed host has a working
# `hermes` command. Installed system-wide under /usr/local (FHS layout); the
# installer runs with --skip-browser --skip-computer-use because this is a
# server/OS image, not a browser host (see build/scripts/install-hermes.sh).
# HERMES_HOME is baked into the image env so the committed dependency
# environment resolves for a bare `podman run ... hermes`, not just a login
# shell — this mirrors the upstream Hermes image's `ENV HERMES_HOME`.
RUN bash /tmp/build_scripts/install-hermes.sh
ENV HERMES_HOME=/usr/local/lib/hermes-agent

# --- Cloudflare WARP client -------------------------------------------------
# Cloudflare ships a single RPM bundling warp-cli, warp-svc and a desktop GUI.
# The GUI's hard Requires pull WebKitGTK/GStreamer, so weak dependencies are
# skipped to trim ~245 MB; warp-cli/warp-svc never use them.
# The RPM %post enables warp-svc.service, which is then disabled again: the
# client needs explicit registration and admins opt in with
# `systemctl enable --now warp-svc`. This must run before the factory /etc
# snapshot below so the disabled state is what gets restored in container mode.
RUN dnf install -y --setopt=install_weak_deps=False cloudflare-warp && \
    systemctl disable warp-svc && \
    dnf clean all

# --- Factory /etc snapshot -------------------------------------------------
# etc-overlay-sync.service restores this snapshot over /etc on every container
# boot. Runtime-owned files must NOT be baked into the snapshot: copying a
# stale copy back over /etc re-clobbers the value the runtime just generated.
# The most damaging case is machine-id — systemd writes it during early boot,
# and a re-zeroed id kills user@UID.service and every D-Bus session bus that
# needs a machine id (code 49 / "Invalid machine ID"). hostname and resolv.conf
# are likewise owned by the container runtime, and the build-time hostname must
# not leak into every instance. The sync script skips these paths as well; keep
# the two lists in sync.
RUN mkdir -p /usr/share/factory/etc && cp -a /etc/. /usr/share/factory/etc/ && \
    rm -f /usr/share/factory/etc/machine-id \
          /usr/share/factory/etc/machine-info \
          /usr/share/factory/etc/hostname \
          /usr/share/factory/etc/resolv.conf

RUN bootc container lint

ENTRYPOINT [ "/sbin/init" ]