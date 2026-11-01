# Workstation (Alma) — bare-bones KDE Plasma 6 desktop base on AlmaLinux 10 bootc.
#
# This is the GUI base image: KDE Plasma Workspaces, Plasma Login Manager,
# Flatpak + Discover's Flatpak backend, a native browser, and the hardware/
# filesystem/codec support that cannot come from Flatpak or AppImage.
# Application-layer packages (office, PIM, multimedia apps, dev tools,
# virtualization, gaming) belong in derived variants.
FROM ghcr.io/braccae/alma:latest

LABEL containers.bootc 1

# --- KDE Plasma desktop environment -----------------------------------------
# The comps environment group provides Plasma, KWin, Plasma Login Manager,
# Dolphin, Konsole, Ark, Spectacle, KWrite, System Settings, Discover,
# Flatpak, xdg-desktop-portal-kde, PipeWire/WirePlumber, Bluetooth, printing,
# power management, fonts, and Breeze GTK.
#
# sddm/sddm-kcm: Plasma Login Manager is the Wayland greeter.
# plasma-discover-packagekit / offline-updates: RPM installs and offline
# updates are not supported on bootc; Discover is Flatpak-only.
# PackageKit-command-not-found / gstreamer-plugin: not useful on bootc;
# codecs are shipped directly.
RUN dnf -y group install \
        "KDE Plasma Workspaces" \
        --exclude=sddm \
        --exclude=sddm-kcm \
        --exclude=plasma-discover-packagekit \
        --exclude=plasma-discover-offline-updates \
        --exclude=PackageKit-command-not-found \
        --exclude=PackageKit-gstreamer-plugin \
    && dnf clean all

# --- Core desktop pins, firmware, graphics/VA-API, codecs -------------------
# Most of these are already pulled by the group; they are pinned so the base
# keeps its intended features if comps changes. GPU/CPU firmware and the
# VA-API drivers are listed explicitly because EL10's linux-firmware wrapper
# pulls no subpackages and the media stack must not depend on comps ordering.
RUN dnf install -y \
        plasma-login-manager \
        flatpak \
        flatpak-selinux \
        plasma-discover-flatpak \
        xdg-desktop-portal-kde \
        wireplumber \
        breeze-gtk-common \
        breeze-gtk-gtk3 \
        breeze-gtk-gtk4 \
        kio-extras \
        kio-admin \
        kio-gdrive \
        kdenetwork-filesharing \
        plasma-print-manager \
        plasma-nm \
        kscreen \
        kinfocenter \
        plasma-systemmonitor \
        kf6-kwallet \
        bluedevil \
        kdnssd \
        dolphin \
        dolphin-plugins \
        konqueror \
        linux-firmware \
        amd-gpu-firmware \
        intel-gpu-firmware \
        nvidia-gpu-firmware \
        amd-ucode-firmware \
        microcode_ctl \
        alsa-sof-firmware \
        alsa-firmware \
        alsa-ucm \
        alsa-tools-firmware \
        fwupd \
        libva \
        libva-utils \
        libva-intel-driver \
        libva-intel-hybrid-driver \
        intel-media-driver \
        libva-nvidia-driver \
        mesa-dri-drivers \
        mesa-libEGL \
        mesa-libGL \
        mesa-vulkan-drivers \
        vulkan-loader \
        libvdpau \
        ffmpeg \
        libavcodec-freeworld \
        libheif-freeworld \
        gstreamer1-plugin-libav \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly \
    && dnf clean all

# --- Filesystems, removable devices, printing -------------------------------
# exFAT: kernel module + exfatprogs. NTFS: ntfs-3g (EL10 has no ntfs3 module).
# APFS: apfs-fuse (read-only). MTP: libmtp + gvfs-mtp + KDE kio-extras.
# Apple iOS: ifuse/libimobiledevice/usbmuxd. Samba/CIFS: base samba-client +
# cifs-utils, plus gvfs-smb and the KDE sharing integration from the group.
RUN dnf install -y \
        exfatprogs \
        ntfs-3g \
        ntfsprogs \
        apfs-fuse \
        dosfstools \
        fuse \
        fuse3 \
        libmtp \
        gvfs \
        gvfs-fuse \
        gvfs-mtp \
        gvfs-smb \
        gvfs-gphoto2 \
        ifuse \
        libimobiledevice \
        libimobiledevice-utils \
        usbmuxd \
        bluez \
        bluez-cups \
        cups-filters \
        cups-filters-driverless \
        cups-browsed \
        hplip \
        cups \
        cups-pk-helper \
        ipp-usb \
        sane-backends \
        sane-backends-drivers-scanners \
        sane-airscan \
    && dnf clean all

# --- Wireless, WWAN, Bluetooth, and firmware breadth ------------------------
# linux-firmware on EL10 is only a wrapper: it requires linux-firmware-whence
# and no firmware subpackages, so every wireless/GPU/audio blob has to be named
# explicitly. The base image installs a subset; pinning the rest keeps Wi-Fi,
# WWAN, USB Wi-Fi, DVB tuners, and newer Intel camera hardware working.
#
# NetworkManager-wifi/-bluetooth/-wwan are separate plugins: without them the
# daemon cannot manage Wi-Fi, Bluetooth PAN, or mobile broadband at all.
RUN dnf install -y \
        iwlwifi-mvm-firmware \
        iwlwifi-dvm-firmware \
        iwlegacy-firmware \
        qcom-firmware \
        libertas-firmware \
        dvb-firmware \
        intel-vsc-firmware \
        NetworkManager-wifi \
        NetworkManager-bluetooth \
        NetworkManager-wwan \
        wpa_supplicant \
        wireless-regdb \
        ModemManager \
        bluez-obexd \
        iw \
        ethtool \
        pciutils \
        usbutils \
    && dnf clean all

# --- Laptop sensors, fingerprint, smartcards, cameras ----------------------
# iio-sensor-proxy: accelerometer/ambient light. libwacom: tablet metadata.
# bolt: Thunderbolt authorization. tuned-ppd: the power-profiles D-Bus API
# backed by the tuned daemon already present in the base image.
RUN dnf install -y \
        iio-sensor-proxy \
        libwacom \
        bolt \
        fprintd \
        fprintd-pam \
        tuned-ppd \
        lm_sensors \
        smartmontools \
        pcsc-lite \
        pcsc-lite-ccid \
        opensc \
        v4l-utils \
        libcamera-tools \
    && dnf clean all

# --- Zeroconf, S3, game controllers, archives, remote apps ------------------
# distrobox: containerised tooling on top of the podman and toolbox already in
# the base image; applications themselves belong in Flatpak.
RUN dnf install -y \
        avahi \
        avahi-tools \
        nss-mdns \
        s3fs-fuse \
        linuxconsoletools \
        steam-devices \
        sdl2-compat \
        libevdev \
        waypipe \
        distrobox \
        7zip \
        unrar \
        zip \
        bsdtar \
    && dnf clean all

# --- ELRepo game-controller HID modules -------------------------------------
# ELRepo is used for prebuilt weak-modules only. kernel-ml is never installed:
# bootc supports exactly one kernel under /usr/lib/modules, and
# `bootc container lint` fails when a second one appears.
# ELRepo ships the in-tree xpad/hid-playstation/hid-nintendo modules that the
# EL10 kernel package omits. The package is built for an older kernel; the
# weak-modules call links it into the image kernel's weak-updates directory.
# Scriptlets are skipped to avoid dracut trying to build an initramfs in the
# container; game controllers are runtime-only modules.
RUN dnf install -y --nogpgcheck https://www.elrepo.org/elrepo-release-10.el10.elrepo.noarch.rpm && \
    dnf install -y --setopt=tsflags=noscripts kmod-game-controllers && \
    find /lib/modules/*/extra/game-controllers -name '*.ko' | \
        /usr/sbin/weak-modules --add-modules --no-initramfs && \
    dnf clean all

# Trim build-time package-manager state. /var is runtime state on bootc; the
# immutable /etc snapshot lives in /usr/share/factory/etc.
RUN rm -rf /var/cache/dnf /var/cache/PackageKit /var/cache/app-info \
           /var/lib/dnf /var/log/dnf*.log /var/log/hawkey.log

# Overlay: system-wide Flathub remote, ZRAM, Bitwarden polkit action, and the
# in-image modinfo fallback. SDDM configuration has been removed.
COPY rootfs/workstation-alma/ /

# Graphical boot via Plasma Login Manager (Alias=display-manager.service).
# Services that are D-Bus or udev activated (bolt, fprintd, iio-sensor-proxy,
# ipp-usb) need no enablement; the units below are the ones that do:
#   cups.socket/cups-browsed  driverless + discovered printers and scanners
#   avahi-daemon.socket      mDNS/DNS-SD discovery (also for remote CUPS)
#   tuned-ppd.service        power-profiles API for Plasma's powerdevil
#   pcscd.socket             smartcard readers
# firewalld blocks mDNS on the public zone, which breaks automatic printer and
# scanner discovery; allow the service permanently. Fingerprint login needs
# the authselect feature in addition to fprintd-pam.
RUN systemctl set-default graphical.target && \
    systemctl enable plasmalogin.service \
        cups.socket \
        cups-browsed.service \
        avahi-daemon.socket \
        bluetooth.service \
        tuned-ppd.service \
        ModemManager.service \
        pcscd.socket && \
    firewall-offline-cmd --zone=public --add-service=mdns && \
    authselect enable-feature with-fingerprint

RUN bootc container lint

ENTRYPOINT ["/usr/lib/systemd/systemd"]
