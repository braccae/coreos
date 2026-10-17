#!/usr/bin/env bash
set -euo pipefail

# Debug logging (mirrors build-zfs.sh)
exec 1> >(tee -a /tmp/thinkpad-build.log)
exec 2> >(tee -a /tmp/thinkpad-build.log >&2)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# --- Configuration -----------------------------------------------------------
TP_SMAPI_VERSION="${TP_SMAPI_VERSION:-0.45}"
RPM_OUT="${RPM_OUT:-/tmp/zfs-rpms}"
ARCH="$(uname -m)"

log "Starting ThinkPad (tp_smapi) kernel module build"
log "TP_SMAPI_VERSION: ${TP_SMAPI_VERSION}"
log "Architecture: ${ARCH}"

# tp_smapi drives the SMAPI BIOS through x86 IO ports; it cannot build or run
# on non-x86 architectures. Skip cleanly so the arm64 matrix leg stays green.
if [ "${ARCH}" != "x86_64" ]; then
    log "SKIP: tp_smapi is x86-only (arch=${ARCH}); nothing to build on this architecture."
    exit 0
fi

# --- Detect the bootc kernel (same contract as build-zfs.sh) ------------------
BOOTC_KERNEL_VERSION=""
for kernel_dir in /usr/lib/modules/*/; do
    kernel_version=$(basename "$kernel_dir")
    if [ -f "${kernel_dir}vmlinuz" ]; then
        BOOTC_KERNEL_VERSION="${kernel_version}"
        break
    fi
done

if [ -z "${BOOTC_KERNEL_VERSION}" ]; then
    log "ERROR: No kernel with vmlinuz found in /usr/lib/modules/"
    ls -la /usr/lib/modules/ || true
    exit 1
fi
log "BOOTC_KERNEL_VERSION: ${BOOTC_KERNEL_VERSION}"

# --- Build dependencies ------------------------------------------------------
log "Installing build dependencies..."
dnf install -y \
    gcc \
    make \
    git \
    openssl \
    rpm-build \
    kernel-devel \
    "kernel-devel-${BOOTC_KERNEL_VERSION}" 2>&1 | tail -2

KERNEL_SOURCE_DIR=$(find /usr/src/kernels/ -maxdepth 1 -type d ! -path "/usr/src/kernels/" | head -1)
if [ -z "${KERNEL_SOURCE_DIR}" ]; then
    log "ERROR: No kernel source directory found in /usr/src/kernels/"
    exit 1
fi
log "KERNEL_SOURCE_DIR: ${KERNEL_SOURCE_DIR}"

# --- Fetch source ------------------------------------------------------------
log "Fetching tp_smapi ${TP_SMAPI_VERSION}..."
cd /tmp
rm -rf tp_smapi
git clone --depth 1 --branch "tp-smapi/${TP_SMAPI_VERSION}" \
    https://github.com/linux-thinkpad/tp_smapi.git tp_smapi 2>&1 | tail -2
cd /tmp/tp_smapi

# --- Build modules against the target kernel ---------------------------------
log "Building modules against ${BOOTC_KERNEL_VERSION}..."
make KVER="${BOOTC_KERNEL_VERSION}" 2>&1 | tail -25

for ko in tp_smapi.ko thinkpad_ec.ko; do
    if [ ! -f "${ko}" ]; then
        log "ERROR: expected module ${ko} was not produced"
        exit 1
    fi
done
log "✓ Built modules: $(ls ./*.ko | xargs -n1 basename | tr '\n' ' ')"

# --- Sign with the MOK key when available ------------------------------------
# Modules left unsigned are rejected by the kernel under Secure Boot + lockdown,
# exactly as the ZFS modules are today. We sign when the MOK secret is mounted.
SIGN_FILE="${KERNEL_SOURCE_DIR}/scripts/sign-file"
MOK_KEY="${MOK_KEY:-/run/secrets/LOCALMOK}"
MOK_DER="${MOK_DER:-/etc/pki/mok/LOCALMOK.der}"

if [ -f "${MOK_KEY}" ] && [ -f "${MOK_DER}" ] && [ -x "${SIGN_FILE}" ]; then
    log "Signing modules with the MOK key..."
    openssl x509 -inform DER -in "${MOK_DER}" -outform PEM -out /tmp/mok.pub.pem
    for ko in tp_smapi.ko thinkpad_ec.ko; do
        "${SIGN_FILE}" sha512 "${MOK_KEY}" /tmp/mok.pub.pem "${ko}"
        signer=$(modinfo -F signer "./${ko}")
        log "  signed ${ko} (signer: ${signer:-<none>})"
    done
    rm -f /tmp/mok.pub.pem
else
    log "⚠ MOK secret not mounted or sign-file unavailable — modules left UNSIGNED."
    log "  (They will load only with Secure Boot disabled or module signature enforcement relaxed.)"
fi

# --- Package RPMs ------------------------------------------------------------
log "Packaging RPMs into ${RPM_OUT}..."
mkdir -p "${RPM_OUT}"
mkdir -p /tmp/rpmbuild/{SPECS,RPMS,SOURCES,BUILD,BUILDROOT}
cp tp_smapi.ko thinkpad_ec.ko /tmp/rpmbuild/SOURCES/

cat > /tmp/rpmbuild/SPECS/tp_smapi-kmod.spec <<SPEC
Name:           kmod-tp_smapi
Version:        ${TP_SMAPI_VERSION}
Release:        1
Summary:        tp_smapi SMAPI BIOS driver for legacy Lenovo ThinkPads
License:        GPL-2.0-only
URL:            https://github.com/linux-thinkpad/tp_smapi
BuildArch:      ${ARCH}
%global         kver ${BOOTC_KERNEL_VERSION}
Provides:       kmod-tp_smapi-kmod = %{version}-%{release}

%description
tp_smapi and thinkpad_ec expose the SMAPI BIOS interface on Lenovo ThinkPads
that route SMAPI through IO-port writes (roughly T4x through *20 models).
It is the canonical out-of-tree ThinkPad driver; models from *30 onward are
covered by the in-tree thinkpad_acpi driver instead.

%install
mkdir -p %{buildroot}/usr/lib/modules/%{kver}/extra
install -m 0644 %{_sourcedir}/tp_smapi.ko    %{buildroot}/usr/lib/modules/%{kver}/extra/
install -m 0644 %{_sourcedir}/thinkpad_ec.ko %{buildroot}/usr/lib/modules/%{kver}/extra/

%files
/usr/lib/modules/%{kver}/extra/tp_smapi.ko
/usr/lib/modules/%{kver}/extra/thinkpad_ec.ko

%changelog
* $(date '+%a %b %d %Y') Build Service <noreply@localhost> - ${TP_SMAPI_VERSION}-1
- Initial tp_smapi kmod build for kernel %{kver}
SPEC

rpmbuild -bb --define "_topdir /tmp/rpmbuild" \
    /tmp/rpmbuild/SPECS/tp_smapi-kmod.spec 2>&1 | tail -6

RPM_FILE=$(find /tmp/rpmbuild/RPMS -type f -name "*.rpm" | head -1)
if [ -z "${RPM_FILE}" ]; then
    log "ERROR: rpmbuild produced no RPM"
    exit 1
fi
cp -v "${RPM_FILE}" "${RPM_OUT}/"

log "✓ tp_smapi build complete"
log "  RPMs in ${RPM_OUT}:"
find "${RPM_OUT}" -maxdepth 1 -type f -name "*.rpm" -exec ls -la {} \; | while read -r line; do
    log "    ${line}"
done
log "Build log: /tmp/thinkpad-build.log"
