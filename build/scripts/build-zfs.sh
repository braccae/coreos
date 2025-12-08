#!/usr/bin/env bash
set -euo pipefail

# Debug logging
exec 1> >(tee -a /tmp/zfs-build.log)
exec 2> >(tee -a /tmp/zfs-build.log >&2)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Get variables from environment and arguments
ZFS_VERSION="${ZFS_VERSION:-zfs-2.3.4}"

log "Starting complete ZFS build process"
log "ZFS_VERSION: ${ZFS_VERSION}"

# Get bootc kernel version - find the kernel directory that contains a vmlinuz file
BOOTC_KERNEL_VERSION=""
for kernel_dir in /usr/lib/modules/*/; do
    kernel_version=$(basename "$kernel_dir")
    # Check if this kernel directory itself contains a vmlinuz file
    if [ -f "${kernel_dir}vmlinuz" ]; then
        BOOTC_KERNEL_VERSION="${kernel_version}"
        log "Found kernel with vmlinuz in modules dir: ${BOOTC_KERNEL_VERSION}"
        break
    fi
done

if [ -z "$BOOTC_KERNEL_VERSION" ]; then
    log "ERROR: No kernel with vmlinuz found in /usr/lib/modules/"
    log "Available kernel directories:"
    ls -la /usr/lib/modules/ || log "Directory /usr/lib/modules/ does not exist"
    exit 1
fi
log "BOOTC_KERNEL_VERSION: ${BOOTC_KERNEL_VERSION}"

# Step 0.5: Check if kernel-devel is already installed
KERNEL_DEVEL_INSTALLED=0
if rpm -q kernel-devel > /dev/null 2>&1; then
    log "✓ kernel-devel is already installed"
    KERNEL_DEVEL_INSTALLED=1
else
    log "kernel-devel not found, will install from standard repos or akmods"
    
    # Check for akmods kernel devel packages as fallback
    AKMODS_MOUNT="/tmp/ublue/akmods"
    if [ -d "$AKMODS_MOUNT" ]; then
        log "Found akmods mount point at $AKMODS_MOUNT"
        # Extract base kernel version (e.g., 6.17.7 from 6.17.7-ba19.fc43.x86_64)
        BASE_KERNEL_VERSION=$(echo "$BOOTC_KERNEL_VERSION" | cut -d- -f1)
        log "Looking for kernel packages matching base version: ${BASE_KERNEL_VERSION}"
        
        # Find all kernel RPMs matching the base version in akmods
        KERNEL_RPMS=$(find "$AKMODS_MOUNT/kernel-rpms" -name "kernel*-${BASE_KERNEL_VERSION}-*.rpm" -type f 2>/dev/null | grep -v debuginfo | grep -v debugsource || true)
        
        if [ -n "$KERNEL_RPMS" ]; then
            log "Found kernel RPMs in akmods:"
            echo "$KERNEL_RPMS" | while read -r rpm; do
                log "  - $(basename "$rpm")"
            done
            
            log "Installing kernel packages from akmods..."
            # Install all matching kernel RPMs (core, devel, modules, etc.)
            echo "$KERNEL_RPMS" | xargs dnf install -y
            KERNEL_DEVEL_INSTALLED=1
            log "✓ Kernel packages from akmods installed successfully"
        else
            log "No kernel RPMs found in akmods matching version ${BASE_KERNEL_VERSION}"
        fi
    fi
fi

# Step 1: Install build dependencies
log "Installing build dependencies..."
dnf install -y \
    wget \
    gcc \
    make \
    autoconf \
    automake \
    libtool \
    rpm-build \
    kernel-rpm-macros \
    libtirpc-devel \
    libblkid-devel \
    libuuid-devel \
    systemd-devel \
    openssl-devel \
    zlib-ng-compat-devel \
    libaio-devel \
    libattr-devel \
    libffi-devel \
    libunwind-devel \
    python3 \
    python3-devel \
    python3-cffi \
    python3-setuptools \
    openssl \
    ncompress \
    tree \
    $([ "$KERNEL_DEVEL_INSTALLED" -eq 0 ] && echo "kernel-devel" || true)

log "✓ Build dependencies installed successfully"

# Find the actual kernel source directory
KERNEL_SOURCE_DIR=$(find /usr/src/kernels/ -maxdepth 1 -type d ! -path "/usr/src/kernels/" | head -1)
if [ -z "$KERNEL_SOURCE_DIR" ]; then
    log "ERROR: No kernel source directory found in /usr/src/kernels/"
    log "Available directories in /usr/src/kernels/:"
    ls -la /usr/src/kernels/ || log "Directory /usr/src/kernels/ does not exist"
    exit 1
fi
log "KERNEL_SOURCE_DIR: ${KERNEL_SOURCE_DIR}"

# # Step 1.5: Convert and install MOK keys for kernel module signing
# log "Converting MOK keys for kernel module signing..."

# # Check if MOK keys exist
# if [ ! -f "/run/secrets/LOCALMOK" ]; then
#     log "ERROR: MOK private key not found at /run/secrets/LOCALMOK"
#     exit 1
# fi

# if [ ! -f "/etc/pki/mok/LOCALMOK.der" ]; then
#     log "ERROR: MOK public key not found at /etc/pki/mok/LOCALMOK.der"
#     exit 1
# fi

# # Create certs directory if it doesn't exist
# mkdir -p "${KERNEL_SOURCE_DIR}/certs"

# # Convert private key from DER to PEM format
# log "Linking MOK private key to kernel source dir..."
# ln -s /run/secrets/LOCALMOK "${KERNEL_SOURCE_DIR}/certs/signing_key.pem"

# # Copy public key to signing location
# log "Converting MOK public key to signing location..."
# openssl x509 -inform DER -in /etc/pki/mok/LOCALMOK.der -outform PEM -out "${KERNEL_SOURCE_DIR}/certs/signing_key.x509"

# # Set proper permissions
# chmod 644 "${KERNEL_SOURCE_DIR}/certs/signing_key.x509"
# ls -al "${KERNEL_SOURCE_DIR}/certs"

# log "✓ MOK keys converted and installed for kernel module signing"

# Step 2: Download and build ZFS
log "Downloading and building ZFS..."
cd /tmp || exit 1

# Download ZFS source
log "Downloading ZFS version: ${ZFS_VERSION}"
wget "https://github.com/openzfs/zfs/releases/download/${ZFS_VERSION}/${ZFS_VERSION}.tar.gz"

# Extract and build
log "Extracting ZFS source..."
tar -xzf "${ZFS_VERSION}.tar.gz"
cd "${ZFS_VERSION}" || exit 1

log "Configuring ZFS build..."
./configure --with-spec=generic

log "Searching for the generated spec file to hardcode the kernel version..."

# Define the list of possible spec directories in order of preference
SPEC_DIRS=("rpm/redhat" "rpm/generic")
SPEC_FILE=""

# Loop through the potential locations until we find the spec file
for dir in "${SPEC_DIRS[@]}"; do
    potential_spec="${dir}/zfs-kmod.spec"
    if [ -f "$potential_spec" ]; then
        SPEC_FILE="$potential_spec"
        log "Found spec file at: ${SPEC_FILE}"
        break
    fi
done

# If the loop completed without finding a file, throw an error.
if [ -z "$SPEC_FILE" ]; then
    log "ERROR: Generated spec file 'zfs-kmod.spec' not found in any of the expected locations!"
    log "Searched in:"
    printf '  - %s\n' "${SPEC_DIRS[@]}"
    exit 1
fi

# Use sed to replace all instances of '$(uname -r)' with the hardcoded version.
# The backslash before '$' is important to prevent shell interpretation.
log "Replacing \$(uname -r) with ${BOOTC_KERNEL_VERSION} in ${SPEC_FILE}"
sed -i "s/\\\$(uname -r)/${BOOTC_KERNEL_VERSION}/g" "$SPEC_FILE"

# Optional but recommended: verify the change was successful.
if grep -q "\$(uname -r)" "$SPEC_FILE"; then
    log "WARNING: \$(uname -r) still found in spec file after patching!"
else
    log "✓ Successfully patched ${SPEC_FILE}"
fi

log "Building ZFS RPMs (this may take a while)..."
make -j1 rpm-utils rpm-kmod

log "✓ ZFS RPMs built successfully"

# Step 3: Grab all installable RPMs in one step
log "Creating directory and copying installable RPMs..."
mkdir -p /tmp/zfs-rpms

log "List of all RPMS found:"
find "/tmp/${ZFS_VERSION}" -type f -name "*.rpm" -print;
log "-----------------------"

find "/tmp/${ZFS_VERSION}" -type f -name "*.rpm" \
  ! -name "*.src.rpm" \
  ! -name "*debuginfo*" \
  ! -name "*debugsource*" \
  ! -name "*devel*" \
  -exec cp -v {} /tmp/zfs-rpms/ \;

RPM_COUNT=$(find /tmp/zfs-rpms/ -maxdepth 1 -type f -name "*.rpm" | wc -l)
log "Found ${RPM_COUNT} installable RPMs"

if [ "$RPM_COUNT" -eq 0 ]; then
    log "ERROR: No installable RPMs found!"
    exit 1
fi

log "✓ Copied installable RPMs to /tmp/zfs-rpms/"

# Final summary
log "=========================================="
log "ZFS build process completed successfully!"
log "=========================================="
log "Summary:"
log "  - ZFS Version: ${ZFS_VERSION}"
log "  - Kernel Version: ${BOOTC_KERNEL_VERSION}"
log ""
log "Userland RPMs available:"
if [ -n "$(find /tmp/zfs-userland/ -maxdepth 1 -type f -name "*.rpm" -print -quit)" ]; then
    find /tmp/zfs-userland/ -maxdepth 1 -type f -name "*.rpm" -exec ls -la {} \; | while read -r line; do
        log "  $line"
    done
else
    log "  (No userland RPMs found)"
fi

log ""
log "Kernel module RPMs available:"
if [ -n "$(find /tmp/zfs-kmod/ -maxdepth 1 -type f -name "*.rpm" -print -quit)" ]; then
    find /tmp/zfs-kmod/ -maxdepth 1 -type f -name "*.rpm" -exec ls -la {} \; | while read -r line; do
        log "  $line"
    done
else
    log "  (No kernel module RPMs found)"
fi

log ""
log "Build log available at: /tmp/zfs-build.log"
log "ZFS build process finished successfully"