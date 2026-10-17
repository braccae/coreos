#!/usr/bin/env bash
# =============================================================================
# build-nix-base-disk.sh
#
# Build a bootc qcow2 that the nix VM validation modes
# (build/scripts/validate-nix-vm-ssh.sh) can boot and prove Nix against.
#
# The source container image MUST already contain:
#   * the nix stack (nix RPM + nix.mount + nix-daemon.socket + the nix SELinux
#     module), so `nix` works under SELinux enforcing, AND
#   * the BUG-5 sshd host-key SELinux fix (build/selinux/sshd/* +
#     /var/lib/sshd tmpfiles d+Z), so sshd actually starts under enforcing.
#
# Without BOTH, the VM mode cannot pass: a nix-only image has sshd fail under
# enforcing (no host keys), and an sshd-only image has no nix.  The canonical
# source tag for a validated image is therefore an image built from a checkout
# that carries both changes, e.g. `localhost/alma:bug5-fixed` (task/bug5-sshd)
# or your own `localhost/alma:nix-base`.
#
# Usage:
#   build/scripts/build-nix-base-disk.sh [image] [tag] [outdir]
#
#   image   podman image repo to BIB from           (default: localhost/alma)
#   tag     podman image tag  to BIB from           (default: nix-base)
#   outdir  output directory for the qcow2 tree     (default: output/alma/nix-base)
#
# Examples:
#   # from the current checkout's image:
#   podman build -t localhost/alma:nix-base .
#   build/scripts/build-nix-base-disk.sh
#
#   # from the BUG-5-fixed image already in podman storage:
#   build/scripts/build-nix-base-disk.sh localhost/alma bug5-fixed
#
# Result: <outdir>/qcow2/disk.qcow2  — pass its path as $BASE_DISK to the
#         validate-nix-vm-*.sh scripts.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WD="$(cd "$HERE/../.." && pwd)"
cd "$WD"

IMAGE="${1:-localhost/alma}"
TAG="${2:-nix-base}"
OUTDIR="${3:-output/alma/nix-base}"
CONFIG="${CONFIG:-$WD/build/config-img.toml}"
BIB_IMAGE="${BIB_IMAGE:-quay.io/centos-bootc/bootc-image-builder:latest}"

say() { printf '%s\n' "$*"; }

say "=== nix base disk build ==="
say "  source image : ${IMAGE}:${TAG}"
say "  config       : ${CONFIG}"
say "  output       : ${OUTDIR}"

command -v podman >/dev/null 2>&1 || { say "FAIL: podman not found"; exit 1; }
command -v sudo   >/dev/null 2>&1 || { say "FAIL: sudo not found";   exit 1; }

# The source image must exist in rootful storage (BIB runs as root).
if ! sudo podman image exists "${IMAGE}:${TAG}"; then
    say "FAIL: ${IMAGE}:${TAG} not present in rootful podman storage."
    say "      Build it first, e.g.:"
    say "        podman build -t ${IMAGE}:${TAG} .            # current checkout"
    say "      or pull a published tag:"
    say "        sudo podman pull ${IMAGE}:${TAG}"
    exit 1
fi

sudo mkdir -p "$OUTDIR"

say "--- running bootc-image-builder (qcow2, xfs, config: ${CONFIG##*/}) ---"
sudo podman run \
    --rm \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${CONFIG}:/config.toml:ro" \
    -v "${WD}/${OUTDIR}:/output" \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "$BIB_IMAGE" \
    --type qcow2 \
    --use-librepo=True \
    --rootfs xfs \
    --config /config.toml \
    "${IMAGE}:${TAG}"

sudo chown -fR "${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}" "./${OUTDIR}" 2>/dev/null || true

DISK="${WD}/${OUTDIR}/qcow2/disk.qcow2"
if [ -r "$DISK" ]; then
    say "PASS: base disk ready"
    say "      BASE_DISK=${DISK}"
    ls -l "$DISK"
else
    say "FAIL: expected qcow2 not found at ${DISK}"
    exit 1
fi
