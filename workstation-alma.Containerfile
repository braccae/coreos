# Workstation (Alma) — bare-bones KDE Plasma 6 desktop base on AlmaLinux 10 bootc.
#
# This is the GUI base image: KDE Plasma Workspaces, Plasma Login Manager,
# Flatpak + Discover's Flatpak backend, a native browser, and the hardware/
# filesystem/codec support that cannot come from Flatpak or AppImage.
# Application-layer packages (office, PIM, multimedia apps, dev tools,
# virtualization, gaming) belong in derived variants.
FROM ghcr.io/braccae/alma:latest

LABEL containers.bootc 1

# --- KDE Plasma desktop environment, core pins, firmware, VA-API, codecs ----
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-alma-kde && \
    just -f /tmp/build.justfile install-alma-desktop-core && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Peripherals, wireless/laptop firmware, extras, ELRepo game controllers -
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-alma-desktop-peripherals && \
    just -f /tmp/build.justfile install-elrepo-game-controllers && \
    just -f /tmp/build.justfile cleanup-dnf

# --- Local overlay (late for optimal layer caching) -------------------------
# System-wide Flathub remote, ZRAM, Bitwarden polkit action, and the in-image
# modinfo fallback.
COPY rootfs/workstation-alma/ /

# --- Final configuration, factory /etc snapshot, and bootc lint -------------
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile configure-alma-workstation && \
    just -f /tmp/build.justfile snapshot-factory-etc && \
    bootc container lint

ENTRYPOINT ["/usr/lib/systemd/systemd"]
