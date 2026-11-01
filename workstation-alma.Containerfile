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
# Every package in this layer except falkon is already pulled by the group;
# they are pinned so the base keeps its intended features if comps changes.
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
        kdnssd \
        falkon \
        linux-firmware \
        alsa-sof-firmware \
        alsa-firmware \
        fwupd \
        libva \
        libva-utils \
        libva-intel-driver \
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
    && dnf clean all

# --- Zeroconf, S3, game controllers, archives, remote apps ------------------
RUN dnf install -y \
        avahi \
        avahi-tools \
        nss-mdns \
        s3fs-fuse \
        linuxconsoletools \
        sdl2-compat \
        libevdev \
        waypipe \
        7zip \
        unrar \
        zip \
        bsdtar \
    && dnf clean all

# Trim build-time package-manager state. /var is runtime state on bootc; the
# immutable /etc snapshot lives in /usr/share/factory/etc.
RUN rm -rf /var/cache/dnf /var/cache/PackageKit /var/cache/app-info \
           /var/lib/dnf /var/log/dnf*.log /var/log/hawkey.log

# Overlay: system-wide Flathub remote, ZRAM, Bitwarden polkit action, and the
# in-image modinfo fallback. SDDM configuration has been removed.
COPY rootfs/workstation-alma/ /

# Graphical boot via Plasma Login Manager (Alias=display-manager.service).
RUN systemctl set-default graphical.target && \
    systemctl enable plasmalogin.service

RUN bootc container lint

ENTRYPOINT ["/usr/lib/systemd/systemd"]
