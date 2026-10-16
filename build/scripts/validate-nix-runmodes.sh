#!/usr/bin/env bash
# =============================================================================
# validate-nix-runmodes.sh
#
# Proves Nix works end-to-end in each supported run mode: in every mode it
# installs a real package from nixpkgs and executes its binary, capturing the
# evidence under output/evidence/nix-<mode>/<UTC-ts>/.
#
# Modes (see docs/mode-spec.md for the mode contract):
#   app     - (mode "rootless-app")    single-app, NO systemd/init. The nix
#             workload runs as PID 1 of a throwaway container.
#   systemd - (mode "rootless-multi" / "rootless-systemd") multi-process
#             container with systemd as PID 1, run rootless.
#   vm      - (mode "bootc-vm")        full bootc OS booted in libvirt/QEMU,
#             nix exercised over SSH. Requires sudo + KVM.
#
# Usage:
#   build/scripts/validate-nix-runmodes.sh [app|systemd|vm|all]
#
# Env overrides:
#   IMAGE=localhost/alma:nix-test   container image under test
#   PKG=hello                       nixpkgs attribute to install/execute
#   CHANNEL=https://nixos.org/channels/nixpkgs-unstable
#   VM_IMAGE=alma  VM_TAG=latest    bootc image ref for the vm mode
#
# Exit code: 0 only when every executed mode passed. Modes that cannot run in
# the current environment (e.g. no sudo for "vm") are reported as "skipped"
# and do NOT fail the run.
# =============================================================================
set -uo pipefail

IMAGE="${IMAGE:-localhost/alma:nix-test}"
PKG="${PKG:-hello}"
CHANNEL="${CHANNEL:-https://nixos.org/channels/nixpkgs-unstable}"
VM_IMAGE="${VM_IMAGE:-alma}"
VM_TAG="${VM_TAG:-latest}"
EVID_ROOT="${EVID_ROOT:-output/evidence}"

MODE="${1:-all}"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
new_evid_dir() {
    local mode="$1"
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    local d="${EVID_ROOT}/nix-${mode}/${ts}"
    mkdir -p "$d"
    printf '%s' "$d"
}

# The nix workload that runs INSIDE the container. It is deliberately small:
# add a channel, install one package from nixpkgs, execute its binary.
# Note: bootc/Alma images symlink /root -> /var/roothome which does not exist
# in a plain container; nix-channel as root needs a writable HOME, so we create
# the home dir and point HOME at it.
nix_workload() {
    cat <<'EOS'
set -euo pipefail
mkdir -p /var/roothome
export HOME=/var/roothome
echo "== nix version =="
nix --version
echo "== nix-channel add =="
nix-channel --add __CHANNEL__ nixpkgs
echo "== nix-channel update =="
nix-channel --update
echo "== nix-env install __PKG__ =="
nix-env -iA nixpkgs.__PKG__
BIN="$HOME/.nix-profile/bin/__PKG__"
echo "== which =="
ls -l "$BIN"
echo "== execute =="
"$BIN"
echo "== NIX_WORKLOAD_OK =="
EOS
}

workload_for_mode() {
    nix_workload | sed "s|__CHANNEL__|${CHANNEL}|g; s|__PKG__|${PKG}|g"
}

write_result() {
    local dir="$1" mode="$2" res="$3" started="$4" extra="${5:-}"
    local ended
    ended="$(date -u +%Y%m%dT%H%M%SZ)"
    cat > "${dir}/result.json" <<EOF
{
  "mode": "nix-${mode}",
  "image": "${IMAGE}",
  "package": "${PKG}",
  "started": "${started}",
  "ended": "${ended}",
  "result": "${res}"${extra}
}
EOF
}

# ---------------------------------------------------------------------------
# Mode "app" — single-app, no systemd/init
# ---------------------------------------------------------------------------
run_app() {
    local started dir
    started="$(date -u +%Y%m%dT%H%M%SZ)"
    dir="$(new_evid_dir app)"
    echo ">>> nix-${PKG} in single-app (no-systemd) container, image=${IMAGE}"
    # --entrypoint "" clears the bootc ENTRYPOINT [/sbin/init] so our command is PID 1.
    if podman run --rm --entrypoint "" "$IMAGE" bash -c "$(workload_for_mode)" \
            > "${dir}/workload.log" 2>&1; then
        write_result "$dir" app pass "$started" ',
  "pid1": "bash"'
        echo "PASS: nix-app  (evidence: ${dir})"
        return 0
    fi
    write_result "$dir" app fail "$started"
    echo "FAIL: nix-app  (see ${dir}/workload.log)"
    return 1
}

# ---------------------------------------------------------------------------
# Mode "systemd" — rootless multi-process container, systemd as PID 1
#
# NOTE: podman's default rootless capability set DROPS CAP_SYS_ADMIN (verified
# via /proc/1/status in a --systemd=always container). Without it, the shipped
# nix.mount unit (bind /var/lib/nix -> /nix) cannot perform its mount and the
# unit lands in `failed`. The nix workload itself still works without the cap,
# but the /nix persistence feature does not. We therefore start the container
# with `--cap-add SYS_ADMIN` (still rootless — NOT --privileged) so nix is
# exercised end-to-end including the persistent store.
# ---------------------------------------------------------------------------
run_systemd() {
    local started dir cname rc=0
    started="$(date -u +%Y%m%dT%H%M%SZ)"
    dir="$(new_evid_dir systemd)"
    cname="nixval-systemd"
    echo ">>> nix-${PKG} in rootless multi-process systemd container, image=${IMAGE}"

    podman rm -f "$cname" >/dev/null 2>&1 || true
    if ! podman run -d --name "$cname" --systemd=always --cap-add SYS_ADMIN "$IMAGE" >/dev/null 2>&1; then
        write_result "$dir" systemd fail "$started"
        echo "FAIL: nix-systemd — container failed to start"
        return 1
    fi

    # Wait for systemd to finish booting. `systemctl is-system-running --wait`
    # needs the system D-Bus socket, which does not exist until systemd has
    # progressed; calling it immediately races the boot. Poll until the bus is
    # reachable and systemd reaches a settled state, or until we time out.
    local sys_state="" waited=0
    while [ "$waited" -lt 90 ]; do
        sys_state="$(podman exec "$cname" systemctl is-system-running 2>/dev/null | tr -d '[:space:]')"
        case "$sys_state" in
            running|degraded|maintenance) break ;;
        esac
        sleep 2; waited=$((waited + 2))
    done
    printf '%s\n' "${sys_state:-timeout}" > "${dir}/systemd-state.txt"
    # Give nix.mount / nix-daemon.socket a moment to reach steady state.
    podman exec "$cname" systemctl is-active nix.mount > "${dir}/nix-mount-active.txt" 2>&1 || true
    podman exec "$cname" systemctl is-active nix-daemon.socket > "${dir}/nix-daemon-socket-active.txt" 2>&1 || true
    podman exec "$cname" ps -o comm= -p 1 > "${dir}/pid1.txt" 2>&1 || true

    # Run the nix workload as an exec'd process (systemd stays PID 1).
    if podman exec "$cname" bash -c "$(workload_for_mode)" > "${dir}/workload.log" 2>&1; then
        rc=0
    else
        rc=1
    fi

    podman rm -f "$cname" >/dev/null 2>&1 || true

    local mount_state socket_state sys_state
    mount_state="$(tr -d '[:space:]' < "${dir}/nix-mount-active.txt")"
    socket_state="$(tr -d '[:space:]' < "${dir}/nix-daemon-socket-active.txt")"
    sys_state="$(tr -d '[:space:]' < "${dir}/systemd-state.txt")"

    if [ "$rc" -eq 0 ] && [ "$mount_state" = "active" ] && [ "$socket_state" = "active" ]; then
        write_result "$dir" systemd pass "$started" ",
  \"nix_mount\": \"${mount_state}\",
  \"nix_daemon_socket\": \"${socket_state}\",
  \"systemd_state\": \"${sys_state}\""
        echo "PASS: nix-systemd  (evidence: ${dir})"
        return 0
    fi
    write_result "$dir" systemd fail "$started" ",
  \"nix_mount\": \"${mount_state}\",
  \"nix_daemon_socket\": \"${socket_state}\",
  \"systemd_state\": \"${sys_state}\""
    echo "FAIL: nix-systemd — rc=${rc} mount=${mount_state} socket=${socket_state} (see ${dir}/workload.log)"
    return 1
}

# ---------------------------------------------------------------------------
# Mode "vm" — bootc VM over libvirt/QEMU (requires sudo + KVM)
# ---------------------------------------------------------------------------
run_vm() {
    # Mode "vm" — bootc VM.  Delegates to the fully UNPRIVILEGED ssh path
    # (build/scripts/validate-nix-vm-ssh.sh): qemu-system-x86_64 + KVM, ephemeral
    # overlay, QGA key injection, then install+execute a nixpkgs package in the
    # booted guest over SSH.  No sudo, no libvirt, no passwordless sudo required.
    # The base qcow2 is auto-resolved (or set BASE_DISK=<path>); it must contain
    # both the nix stack and the BUG-5 sshd fix — see build-nix-base-disk.sh.
    local started dir rc
    started="$(date -u +%Y%m%dT%H%M%SZ)"
    dir="$(new_evid_dir vm)"
    echo ">>> nix-${PKG} in bootc VM (ssh path), base disk auto-resolved"

    EVID_DIR="$dir" PKG="$PKG" VM_USER="${VM_USER:-}" \
        bash build/scripts/validate-nix-vm-ssh.sh
    rc=$?

    if [ "$rc" -eq 0 ]; then
        local bd=""
        [ -f "$dir/base-disk.txt" ] && bd="$(cat "$dir/base-disk.txt")"
        write_result "$dir" vm pass "$started" ",
  \"base_disk\": \"${bd}\""
        echo "PASS: nix-vm  (evidence: ${dir})"
        return 0
    elif [ "$rc" -eq 2 ]; then
        write_result "$dir" vm skipped "$started" ',
  "reason": "no readable nix+sshd base disk; build one with build/scripts/build-nix-base-disk.sh"'
        echo "SKIP: nix-vm — no readable base disk (see ${dir}/run.log)"
        return 2
    fi
    write_result "$dir" vm fail "$started"
    echo "FAIL: nix-vm (see ${dir}/run.log)"
    return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
overall=0
case "$MODE" in
    app)     run_app || overall=$? ;;
    systemd) run_systemd || overall=$? ;;
    vm)      run_vm || overall=$?; [ "$overall" -eq 2 ] && overall=0 ;;
    all)
        run_app     || overall=$?
        run_systemd || overall=$?
        run_vm      || overall=$?
        [ "$overall" -eq 2 ] && overall=0   # skipped vm does not fail "all"
        ;;
    *) echo "usage: $0 [app|systemd|vm|all]"; exit 64 ;;
esac

echo
if [ "$overall" -eq 0 ]; then
    echo "RESULT: all executed modes passed"
else
    echo "RESULT: one or more modes FAILED"
fi
exit "$overall"
