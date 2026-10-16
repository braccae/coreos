#!/usr/bin/env bash
# =============================================================================
# validate-nix-vm-ssh.sh   (Mode 3 — bootc VM)
#
# Proves Nix works end-to-end INSIDE a booted bootc VM by:
#   1. installing a real nixpkgs package (hello) using the VM's own nix, and
#   2. executing its binary, capturing stdout.
#
# Access strategy (fully UNPRIVILEGED on the host):
#   * Boot the prebuilt nix-enabled bootc qcow2 under qemu-system-x86_64 + KVM
#     using an ephemeral qcow2 overlay (base image stays untouched).
#   * The image's qemu-guest-agent allowlist permits
#     `guest-ssh-add-authorized-keys`, so we push our ed25519 public key to the
#     admin user's authorized_keys over the QGA virtio-serial channel — no
#     cloud-init, no console login, no pre-provisioned user needed.
#   * SSH in over a host->guest port-forward and run the nix install/exec.
#
# Prereqs: qemu-system-x86_64, qemu-img, ssh, python3, OVMF firmware, and a
#          private key whose .pub matches the key authorized in the disk image
#          (default ~/.ssh/id_ed25519).
#
# Usage:  bash build/scripts/validate-nix-vm-ssh.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WD="$(cd "$HERE/../.." && pwd)"
cd "$WD"

# --- base disk resolution ----------------------------------------------------
# The base qcow2 must contain BOTH the nix stack AND the BUG-5 sshd host-key
# SELinux fix (so sshd starts under enforcing), and a `core` admin user whose
# authorized key matches ${IDKEY}.pub.  Resolution order:
#   1. explicit $BASE_DISK (if set and readable)
#   2. first readable path in the candidate list below
# If nothing usable is found we SKIP (exit 2) and print how to build one with
# build/scripts/build-nix-base-disk.sh — never a silent false pass.
_BASE_CANDIDATES=(
    "$WD/output/alma/nix-base/qcow2/disk.qcow2"
    "$WD/output/alma/nix-test/qcow2/disk.qcow2"
    "/home/pants/Projects/container_projects/coreos/.worktrees/nix-base/output/alma/nix-test/qcow2/disk.qcow2"
    "/home/pants/.hermes/profiles/cody-the-coder/cache/scratch/bug5-vm/bug5-cfg.qcow2"
    "/home/pants/.hermes/profiles/cody-the-coder/cache/scratch/bib-out2/qcow2/disk.qcow2"
)
if [ -n "${BASE_DISK:-}" ] && [ -r "$BASE_DISK" ]; then
    : # honoured below
else
    for _c in "${_BASE_CANDIDATES[@]}"; do
        if [ -r "$_c" ]; then BASE_DISK="$_c"; break; fi
    done
fi
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/x64/OVMF_CODE.4m.fd}"
OVMF_VARS_SRC="${OVMF_VARS_SRC:-/usr/share/OVMF/x64/OVMF_VARS.4m.fd}"
IDKEY="${IDKEY:-$HOME/.ssh/id_ed25519}"
MEM="${MEM:-4096}"
VCPUS="${VCPUS:-2}"
PKG="${PKG:-hello}"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-}"

EVID_DIR="${EVID_DIR:-$WD/output/evidence/nix-vm/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$EVID_DIR"
SERIAL="$EVID_DIR/serial.log"
QGA_SOCK="$WD/output/qga.sock"
PIDFILE="$WD/output/qemu-nixvm.pid"
OVERLAY="$WD/output/nixvm-overlay-$(date -u +%Y%m%dT%H%M%SZ).qcow2"
VARS="$WD/output/OVMF_VARS.nixvm.fd"

log() { printf '%s\n' "$*" | tee -a "$EVID_DIR/run.log"; }

cleanup() {
    if [ -f "$PIDFILE" ]; then
        local p; p="$(cat "$PIDFILE" 2>/dev/null || true)"
        if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
            for _ in $(seq 1 20); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done
            kill -9 "$p" 2>/dev/null || true
        fi
        rm -f "$PIDFILE"
    fi
    rm -f "$QGA_SOCK"
}
trap cleanup EXIT INT TERM

# --- preflight --------------------------------------------------------------
for b in qemu-system-x86_64 qemu-img python3 ssh; do
    command -v "$b" >/dev/null 2>&1 || { log "FAIL: missing binary: $b"; echo "fail" > "$EVID_DIR/result.txt"; exit 1; }
done
[ -r "$BASE_DISK" ] || {
    log "SKIP: no readable base disk found. Set BASE_DISK=<path> or build one:"
    log "        podman build -t localhost/alma:nix-base .   # image with nix + sshd fix"
    log "        build/scripts/build-nix-base-disk.sh"
    echo "skip" > "$EVID_DIR/result.txt"
    exit 2
}
[ -r "${IDKEY}.pub" ] || { log "FAIL: no public key at ${IDKEY}.pub"; echo "fail" > "$EVID_DIR/result.txt"; exit 1; }
[ -r /dev/kvm ] && [ -w /dev/kvm ] || { log "FAIL: /dev/kvm not accessible"; echo "fail" > "$EVID_DIR/result.txt"; exit 1; }

PUBKEY="$(cat "${IDKEY}.pub")"
log ">>> nix-${PKG} in bootc VM (ssh path)"
log "    base disk : $BASE_DISK"
log "    pubkey    : ${PUBKEY%% *} ...${PUBKEY: -12}"
log "    evidence  : $EVID_DIR"

# --- ephemeral overlay + writable vars --------------------------------------
qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_DISK" "$OVERLAY" 20G >/dev/null 2>&1 \
    || { log "FAIL: overlay create"; echo "fail" > "$EVID_DIR/result.txt"; exit 1; }
cp "$OVMF_VARS_SRC" "$VARS" && chmod u+w "$VARS"

if [ -f "$PIDFILE" ]; then
    old="$(cat "$PIDFILE" 2>/dev/null || true)"
    [ -n "$old" ] && kill "$old" 2>/dev/null || true
    rm -f "$PIDFILE"
fi
rm -f "$QGA_SOCK"

# --- boot -------------------------------------------------------------------
qemu-system-x86_64 \
    -enable-kvm -cpu host -m "$MEM" -smp "$VCPUS" \
    -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$VARS" \
    -drive file="$OVERLAY",if=virtio,format=qcow2 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22 \
    -device virtio-net-pci,netdev=net0 \
    -chardev socket,id=qga0,path="$QGA_SOCK",server=on,wait=off \
    -device virtio-serial-pci \
    -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    -display none \
    -serial file:"$SERIAL" \
    -daemonize -pidfile "$PIDFILE" \
    2>>"$EVID_DIR/run.log" \
    || { log "FAIL: qemu did not start"; echo "fail" > "$EVID_DIR/result.txt"; exit 1; }
log "    qemu pid  : $(cat "$PIDFILE")"

# --- QGA: push authorized key ----------------------------------------------
log "    waiting for guest agent + pushing authorized key..."
python3 - "$QGA_SOCK" "$EVID_DIR" "$PUBKEY" "$VM_USER" <<'PY'
import json, os, socket, sys, time

sock_path, evid, pubkey, vm_user = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
deadline = time.time() + 300
dbg = open(os.path.join(evid, "qga-debug.log"), "w")

def connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5); s.connect(sock_path); return s

def rpc(s, obj):
    s.sendall((json.dumps(obj) + "\n").encode())
    buf = b""
    while True:
        try:
            chunk = s.recv(65536)
        except socket.timeout:
            return {"__timeout__": True}
        if not chunk:
            return {"__eof__": True}
        buf += chunk
        for line in buf.replace(b"\x1e", b"\n").split(b"\n"):
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except Exception:
                continue
            if "return" in msg or "error" in msg:
                dbg.write(json.dumps(msg)[:1500] + "\n"); dbg.flush()
                return msg
            # sync marker line, ignore
            continue

s = None
while time.time() < deadline:
    try:
        s = connect(); break
    except Exception:
        time.sleep(2)
if s is None:
    print("QGA_CONNECT_TIMEOUT"); sys.exit(1)

# guest-sync first (older agents need it)
sync = {"execute": "guest-sync", "arguments": {"id": 99}}
s.sendall((json.dumps(sync) + "\n").encode())
s.settimeout(3)
try:
    s.recv(65536)
except Exception:
    pass
s.settimeout(30)

# find users
users_msg = rpc(s, {"execute": "guest-get-users"})
users = []
try:
    users = [u.get("user") for u in users_msg["return"]]
except Exception:
    pass
print("GUEST_USERS", users)

# choose target
target = vm_user
if not target:
    for cand in ("core", "admin", "root"):
        if cand in users:
            target = cand; break
if not target:
    target = "root"
print("TARGET_USER", target)

# add key
r = rpc(s, {"execute": "guest-ssh-add-authorized-keys",
            "arguments": {"username": target, "keys": [pubkey], "reset": False}})
print("ADD_KEY_RESULT", json.dumps(r)[:400])
open(os.path.join(evid, "target-user.txt"), "w").write(target)
PY

TARGET_USER="$(cat "$EVID_DIR/target-user.txt" 2>/dev/null || echo root)"
log "    target user: $TARGET_USER"

# --- wait for sshd, then SSH in and run nix --------------------------------
SSH_OPTS=(-i "$IDKEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes -o LogLevel=ERROR)

ssh_ready=0
for _ in $(seq 1 60); do
    if ssh "${SSH_OPTS[@]}" "${TARGET_USER}@127.0.0.1" true >/dev/null 2>&1; then ssh_ready=1; break; fi
    sleep 3
done
log "    ssh ready: $ssh_ready"

if [ "$ssh_ready" -eq 0 ]; then
    # try root as fallback
    for _ in $(seq 1 20); do
        if ssh "${SSH_OPTS[@]}" "root@127.0.0.1" true >/dev/null 2>&1; then TARGET_USER=root; ssh_ready=1; break; fi
        sleep 3
    done
fi

if [ "$ssh_ready" -eq 0 ]; then
    log "FAIL: could not SSH into the VM (user=$TARGET_USER port=$SSH_PORT)"
    grep -iE "sshd|login:|Failed to start" "$SERIAL" 2>/dev/null | tail -20 > "$EVID_DIR/serial-highlights.txt" || true
    echo "fail" > "$EVID_DIR/result.txt"
    exit 1
fi

ssh "${SSH_OPTS[@]}" "${TARGET_USER}@127.0.0.1" \
  'systemctl is-system-running; echo "---units---"; systemctl is-active nix.mount nix-daemon.socket' \
  > "$EVID_DIR/systemd-state.txt" 2>&1 || true
cat "$EVID_DIR/systemd-state.txt" | tee -a "$EVID_DIR/run.log"

# --- the actual proof: install + execute a nixpkgs package ------------------
ssh "${SSH_OPTS[@]}" "${TARGET_USER}@127.0.0.1" bash -s <<EOF > "$EVID_DIR/guest-run.txt" 2>&1
set -e
export HOME=\$(getent passwd ${TARGET_USER} | cut -d: -f6)
echo "=== user=\$(id -un) home=\$HOME ==="
echo "=== nix version ==="
nix --version
echo "=== nix-channel setup ==="
nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs 2>/dev/null || true
nix-channel --update 2>&1 | tail -2
echo "=== install nixpkgs.${PKG} ==="
nix-env -iA nixpkgs.${PKG} 2>&1 | tail -5
echo "=== execute \$(which ${PKG}) ==="
export PATH="\$HOME/.nix-profile/bin:\$PATH"
${PKG}
EOF
cat "$EVID_DIR/guest-run.txt" | tee -a "$EVID_DIR/run.log"

grep -iE "nix|login:|Failed to start" "$SERIAL" 2>/dev/null | tail -25 > "$EVID_DIR/serial-highlights.txt" || true

if grep -q "Hello, world!" "$EVID_DIR/guest-run.txt"; then
    echo "pass" > "$EVID_DIR/result.txt"
    log "PASS: nix-vm  (evidence: $EVID_DIR)"
    RC=0
else
    echo "fail" > "$EVID_DIR/result.txt"
    log "FAIL: nix-vm — package did not execute cleanly (evidence: $EVID_DIR)"
    RC=1
fi
exit "$RC"
