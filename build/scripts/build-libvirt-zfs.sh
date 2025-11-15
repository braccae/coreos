#!/usr/bin/env bash
set -euo pipefail

echo "Installing dependancies..."

# dnf install -y \
#     wget \
#     rpm-build \
#     libvirt-devel \
#     gcc \
#     meson \
#     ninja-build \
#     libxml2-devel \
#     gnutls-devel \
#     pciutils-devel \
#     procps-ng-devel \
#     libselinux-devel \
#     libtool \
#     dtrace \
#     qemu-img \
#     audit-libs-devel \
#     augeas \
#     cyrus-sasl-devel \
#     device-mapper-devel \
#     firewalld-filesystem \
#     gettext \
#     git \
#     glib2-devel \
#     iscsi-initiator-utils \
#     json-c-devel \
#     libacl-devel \
#     libattr-devel \
#     libblkid-devel \
#     libcap-ng-devel \
#     libcurl-devel \
#     libnl3-devel \
#     libpcap-devel \
#     librdmacm-devel \
#     libseccomp-devel \
#     libtirpc-devel \
#     libuuid-devel \
#     libvirt-client \
#     libxslt-devel \
#     lvm2-devel \
#     numactl-devel \
#     openldap-devel \
#     parted-devel \
#     python3-devel \
#     readline-devel \
#     rpcgen \
#     sanlock-devel \
#     systemd-devel \
#     wget \
#     xfsprogs-devel \
#     libnbd-devel \
#     libpciaccess-devel \
#     librados-devel \
#     librbd-devel \
#     numad \
#     python3-docutils \
#     python3-pytest \
#     systemtap-sdt-devel \
#     wireshark-devel

echo "Starting libvirt build with ZFS driver..."

# --- Setup RPM Build Environment ---
export HOME=/tmp/
RPM_BUILD_DIR="${HOME}/rpmbuild"
mkdir -p "${RPM_BUILD_DIR}/SPECS" \
         "${RPM_BUILD_DIR}/BUILD" \
         "${RPM_BUILD_DIR}/SRPMS" \
         "${RPM_BUILD_DIR}/RPMS"

cd /tmp

# --- 1. Get Libvirt Source RPM (SRPM) ---
# Find currently installed libvirt version to get corresponding SRPM
LIBVIRT_VERSION_FULL=$(dnf list --installed libvirt-daemon | grep libvirt-daemon | awk '{print $2}')
LIBVIRT_VERSION_REL=$(echo $LIBVIRT_VERSION_FULL | awk -F'-' '{print $NF}')
LIBVIRT_VERSION=$(echo $LIBVIRT_VERSION_FULL | sed "s/-$LIBVIRT_VERSION_REL//")

echo "Found installed libvirt version: ${LIBVIRT_VERSION_FULL}"

# Use dnf to download SRPM
dnf download --source libvirt --downloaddir /tmp/ --releasever 10
SRPM_FILE=$(find /tmp/ -maxdepth 1 -name "libvirt-$LIBVIRT_VERSION_FULL.src.rpm" | head -1)

if [ -z "$SRPM_FILE" ]; then
    echo "Error: Could not find libvirt SRPM file."
    exit 1
fi

# Install the SRPM to extract spec file and source tarballs
rpm -i --define "_topdir ${RPM_BUILD_DIR}" "$SRPM_FILE"

# --- 2. Modify SPEC file to enable ZFS driver ---
LIBVIRT_SPEC_FILE="${RPM_BUILD_DIR}/SPECS/libvirt.spec"

echo "Modifying spec file: ${LIBVIRT_SPEC_FILE}"

# 2a. Enable ZFS build flag using multiple approaches
# Check if a ZFS bcond already exists and is commented out:
if grep -q "%bcond_with storage_zfs" "$LIBVIRT_SPEC_FILE"; then
    # Uncomment existing ZFS bcond
    sed -i 's/^# %bcond_with storage_zfs/%bcond_without storage_zfs/' "$LIBVIRT_SPEC_FILE"
    echo "Uncommented existing ZFS bcond"
elif grep -q "%bcond_without storage_zfs" "$LIBVIRT_SPEC_FILE"; then
    # Change bcond_without to bcond_without (enable ZFS)
    sed -i 's/^%bcond_without storage_zfs/%bcond_without storage_zfs/' "$LIBVIRT_SPEC_FILE"
    echo "Changed ZFS bcond_without to enable ZFS"
else
    # Add new ZFS bcond if none exists
    echo "%bcond_without storage_zfs" >> "$LIBVIRT_SPEC_FILE"
    echo "Added new ZFS bcond"
fi

# 2b. Inject ZFS devel dependency if it's missing
if ! grep -q "libzfs6-devel" "$LIBVIRT_SPEC_FILE"; then
    sed -i '/^BuildRequires:.*libaio-devel/a BuildRequires: libzfs6-devel' "$LIBVIRT_SPEC_FILE"
    echo "Added libzfs6-devel BuildRequires"
fi

# 2c. Force enable ZFS in global options
sed -i '/^%global/a %global with_storage_zfs 1' "$LIBVIRT_SPEC_FILE"
echo "Added global with_storage_zfs flag"

# 2d. Patch meson setup if it exists
if grep -q "meson setup" "$LIBVIRT_SPEC_FILE"; then
    sed -i '/meson setup/s/--prefix=%{_prefix}/--prefix=%{_prefix} -Dstorage_zfs=enabled/' "$LIBVIRT_SPEC_FILE"
    echo "Patched meson setup with ZFS flag"
fi

# 2e. Debug output
echo "=== ZFS-related lines in spec file ==="
grep -i "zfs\|storage" "$LIBVIRT_SPEC_FILE" || echo "No ZFS/storage lines found"
echo "===================================="

# --- 3. Build RPMs ---
echo "Building libvirt RPMs..."
rpmbuild -bb --nocheck --define "debug_package %{nil}" --define "_with_sysusers 0" --define "_topdir ${RPM_BUILD_DIR}" "$LIBVIRT_SPEC_FILE"

# --- 4. Move the resulting ZFS driver RPM to output directory ---
OUTPUT_DIR="/tmp/libvirt-rpms"
mkdir -p "$OUTPUT_DIR"

# Find ZFS driver RPM, which should be in RPMS subdirectory
ZFS_DRIVER_RPM=$(find "${RPM_BUILD_DIR}/RPMS" -name "libvirt-daemon-driver-storage-zfs-*.rpm" | head -1)

if [ -f "$ZFS_DRIVER_RPM" ]; then
    mv -v "$ZFS_DRIVER_RPM" "$OUTPUT_DIR/"
    echo "✓ Successfully built ZFS driver RPM: $(basename "$ZFS_DRIVER_RPM")"
else
    echo "⚠ Warning: Failed to find libvirt-daemon-driver-storage-zfs RPM"
    echo "All built RPMs:"
    find "${RPM_BUILD_DIR}/RPMS" -name "*.rpm" | sort
    echo "Copying all storage driver RPMs for inspection..."
    find "${RPM_BUILD_DIR}/RPMS" -name "*storage*.rpm" -exec cp {} "$OUTPUT_DIR/" \;
fi

echo "All RPMs copied to ${OUTPUT_DIR}:"
ls -lh "$OUTPUT_DIR"