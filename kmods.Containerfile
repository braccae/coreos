ARG ZFS_VERSION="zfs-2.4.1"

# ── Fedora ──────────────────────────────────────────────────────────────────
FROM quay.io/fedora/fedora-bootc:43 AS zfs-fedora

ARG ZFS_VERSION
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der
COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh && \
    BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    echo "$BOOTC_KERNEL_VERSION" > /tmp/zfs-rpms/kernel-version.txt

# ── AlmaLinux ───────────────────────────────────────────────────────────────
FROM quay.io/almalinuxorg/almalinux-bootc:10 AS zfs-alma

ARG ZFS_VERSION
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der
COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh && \
    BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    echo "$BOOTC_KERNEL_VERSION" > /tmp/zfs-rpms/kernel-version.txt

# ── Bazzite (workstation) ──────────────────────────────────────────────────
FROM ghcr.io/ublue-os/bazzite:stable-43 AS zfs-bazzite

ARG ZFS_VERSION
COPY keys/mok/LOCALMOK.der /etc/pki/mok/LOCALMOK.der
COPY build/scripts/build-zfs.sh /tmp/build_scripts/zfs.sh
RUN --mount=type=secret,mode=0600,id=LOCALMOK \
    bash /tmp/build_scripts/zfs.sh && \
    BOOTC_KERNEL_VERSION=$(find /usr/lib/modules/ -maxdepth 1 -type d ! -path "/usr/lib/modules/" -printf "%f\n" | head -1) && \
    echo "$BOOTC_KERNEL_VERSION" > /tmp/zfs-rpms/kernel-version.txt

# ── Final scratch image with all variants ──────────────────────────────────
FROM scratch
COPY --from=zfs-fedora  /tmp/zfs-rpms/ /zfs/fedora/
COPY --from=zfs-alma    /tmp/zfs-rpms/ /zfs/alma/
COPY --from=zfs-bazzite /tmp/zfs-rpms/ /zfs/bazzite/