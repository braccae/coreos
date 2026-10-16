# Workstation (Alma) — KDE Plasma 6 desktop workstation variant on AlmaLinux 10 bootc.
FROM ghcr.io/braccae/alma:latest

LABEL containers.bootc 1

# --- Microsoft VS Code repository key ---------------------------------------
# /etc/yum.repos.d/code.repo is baked into the base image; import Microsoft's
# GPG signing key to satisfy rpm signature checks during dnf installation.
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc

# --- KDE Plasma 6 desktop, Wayland + Xwayland, Audio, SDDM, Workstation Tools
# 1. KDE Plasma:
#    plasma-workspace, plasma-desktop, kwin, kdecoration, plasma-breeze,
#    breeze-icon-theme, polkit-kde, konsole, qt6-qtwayland, xorg-x11-server-Xwayland,
#    libxcvt, mesa-dri-drivers, mesa-libEGL, dejavu-sans-fonts, pipewire,
#    wireplumber, pipewire-pulseaudio, pulseaudio-utils, alsa-utils.
# 2. Display Manager:
#    sddm, sddm-kcm.
# 3. Workstation utilities & KDE apps:
#    java-21-openjdk, kmail, merkuro, kde-partitionmanager, yakuake, virt-manager,
#    qemu-kvm, qemu-img, waypipe, mpv, bat.
#    - qemu-kvm-tools substituted for Fedora's qemu-tools.
#    - Virtio GPU / spice / audio modules: in AlmaLinux 10 these are packaged under
#      qemu-kvm-device-display-virtio-gpu, qemu-kvm-device-display-virtio-gpu-pci,
#      qemu-kvm-device-usb-redirect, qemu-kvm-ui-opengl, qemu-kvm-ui-spice.
# 4. Dev Mode:
#    code (VS Code), gh (GitHub CLI).
#
# Base image already provides:
#    git, tmux, sqlite, samba, tuned, realmd, sssd, rclone, borgbackup/borgmatic,
#    nodejs, nodejs-npm, nix, and ZFS kernel modules.
#
# Package substitutions and omissions for AlmaLinux 10 / EPEL 10:
#    - input-leap: omitted; not packaged in EPEL 10 or RPMFusion EL10.
#    - pnpm: omitted from RPM transaction; installed globally via npm below.
#    - ghostty: omitted; Fedora COPR only, no EL10 package available.
#    - fedora-chromium-config-kde: omitted; Fedora-specific config, not in EL10.
#    - plasma-discover-flatpak, plasma-discover-rpm-ostree: omitted; Fedora packaging.
#    - bees: omitted; Fedora deduplication package not in EPEL 10.
#    - XIVLauncher: omitted; Fedora game COPR only.
# Note: chromium, chromium-headless, chromedriver and chromium-qt6-ui ARE available
#    in EPEL 10 (155.0.x) and are installed below to match the bazzite workstation set.
RUN dnf install -y \
        plasma-workspace \
        plasma-desktop \
        kwin \
        kdecoration \
        plasma-breeze \
        breeze-icon-theme \
        polkit-kde \
        konsole \
        qt6-qtwayland \
        xorg-x11-server-Xwayland \
        libxcvt \
        mesa-dri-drivers \
        mesa-libEGL \
        dejavu-sans-fonts \
        pipewire \
        wireplumber \
        pipewire-pulseaudio \
        pulseaudio-utils \
        alsa-utils \
        sddm \
        sddm-kcm \
        java-21-openjdk \
        kmail \
        merkuro \
        kde-partitionmanager \
        yakuake \
        virt-manager \
        qemu-kvm \
        qemu-img \
        qemu-kvm-tools \
        qemu-kvm-device-display-virtio-gpu \
        qemu-kvm-device-display-virtio-gpu-pci \
        qemu-kvm-device-usb-redirect \
        qemu-kvm-ui-opengl \
        qemu-kvm-ui-spice \
        waypipe \
        mpv \
        bat \
        chromium \
        chromium-headless \
        chromedriver \
        chromium-qt6-ui \
        sqlite-devel \
        code \
        gh \
    && dnf clean all

# --- pnpm (dev-mode) ---------------------------------------------------------
# pnpm is not in EPEL 10 RPM repos; install globally using the nodejs-npm toolchain.
# HOME=/tmp avoids bootc /var/roothome missing home directory during build time.
RUN HOME=/tmp npm install -g pnpm && rm -rf /tmp/.npm

# --- core user ---------------------------------------------------------------
# The base image ships NO user: `core` is only provisioned in the disk image,
# via build/config-img.toml. Create it here so the desktop session, SSH and
# podman.socket (SocketGroup=core) all line up. The base already enables linger
# for core (/var/lib/systemd/linger/core) and points sshd's host keys at
# /var/lib/sshd, so nothing else needs adding for SSH or user services.
#
# `video`/`render` (GID 39/105) come from systemd-sysusers: they resolve via NSS
# but are NOT in /etc/group on disk, and useradd/usermod/gpasswd validate against
# /etc/group directly — so `useradd -G wheel,video` fails and `usermod -aG video`
# silently no-ops. Materialize the group lines first, then add membership by GID.
RUN useradd -m -u 1000 -G wheel core && \
    grep -q '^video:'  /etc/group || echo 'video:x:39:'   >> /etc/group; \
    grep -q '^render:' /etc/group || echo 'render:x:105:' >> /etc/group; \
    usermod -aG 39,105 core && \
    echo 'core:webtop' | chpasswd && \
    echo "core ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/core

RUN mkdir -p /home/core/Desktop /home/core/Downloads && \
    chown -R core:core /home/core

# --- filesystem overlay ------------------------------------------------------
# Overlay provides SDDM Wayland configuration, ZRAM generator settings,
# Bitwarden polkit policy, and modinfo fallback helper.
COPY rootfs/workstation-alma/ /

# --- systemd target and display manager enablement --------------------------
RUN systemctl set-default graphical.target && \
    systemctl enable sddm.service

# --- bootc container validation ----------------------------------------------
RUN bootc container lint

ENTRYPOINT ["/usr/lib/systemd/systemd"]
