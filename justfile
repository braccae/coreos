# ==============================================================================
# Preamble with settings and private helper recipes.
# ==============================================================================
set shell := ["bash", "-c"]



# ==============================================================================
# MOK Key Management
# ==============================================================================

# Regenerate the MOK key pair for Secure Boot
# This will overwrite existing keys and require re-enrollment
regen-mok:
    #!/bin/bash
    set -euo pipefail
    echo "=== Regenerating MOK Key Pair ==="
    echo "WARNING: This will overwrite existing MOK keys!"
    echo "You will need to re-enroll the new key in Secure Boot."
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 1
    fi
    
    cd keys/mok
    echo "Generating new MOK key pair..."
    openssl req -new -x509 -newkey rsa:2048 \
        -keyout LOCALMOK.priv \
        -outform DER -out LOCALMOK.der \
        -nodes -days 36500 \
        -subj "/CN=LOCALMOK/"
    chmod 600 LOCALMOK.priv
    
    echo "✓ MOK key pair regenerated successfully"
    echo "Public certificate: $(pwd)/LOCALMOK.der"
    echo "Private key: $(pwd)/LOCALMOK.priv"
    echo
    echo "Next steps:"
    echo "1. Rebuild your container image"
    echo "2. Run: sudo ./keys/enroll-mok.sh"
    echo "3. Reboot and enroll the new key"

# ==============================================================================
# This file is organized into sections based on the scripts they replace.
# ==============================================================================

# ==============================================================================
# Recipes from dev-tools/scripts/install/podman-build-disk-image.sh
# ==============================================================================

# Builds a qcow2 disk image from a container image.
# Usage: just build-disk-image <image> <image_tag>
build-disk-image image='alma' image_tag='latest':
    #!/bin/bash
    set -euo pipefail
    sudo podman pull ghcr.io/braccae/{{image}}:{{image_tag}}
    sudo mkdir -p ./output/{{image}}/{{image_tag}}
    sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./build/config-img.toml:/config.toml:ro \
        -v ./output/{{image}}/{{image_tag}}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 \
        --use-librepo=True \
        --rootfs xfs \
        ghcr.io/braccae/{{image}}:{{image_tag}}
    sudo chown -fR ${SUDO_UID:-${CALLING_UID:-$(id -u)}}:${SUDO_GID:-${CALLING_GID:-$(id -g)}} ./output

build-iso image='alma' image_tag='latest':
    #!/bin/bash
    set -euo pipefail
    sudo podman pull ghcr.io/braccae/{{image}}:{{image_tag}}
    sudo mkdir -p ./output/{{image}}/{{image_tag}}
    sudo podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./build/config-iso.toml:/config.toml:ro \
        -v ./output/{{image}}/{{image_tag}}:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type bootc-installer \
        --use-librepo=True \
        --rootfs btrfs \
        --installer-payload-ref ghcr.io/braccae/{{image}}:{{image_tag}} \
        --verbose \
        ghcr.io/braccae/{{image}}:{{image_tag}}
    sudo chown -fR ${SUDO_UID:-${CALLING_UID:-$(id -u)}}:${SUDO_GID:-${CALLING_GID:-$(id -g)}} ./output

# build-container image='alma' image_tag='latest':
#     podman build \
#         -t {{image}}:{{image_tag}} \
#         . \
#         -f {{image_tag}}.Containerfile
# ==============================================================================
# Recipes from dev-tools/scripts/install/write-disk-image-to-disk.sh
# ==============================================================================

# Writes a disk image to a block device.
# DANGER: This will overwrite the destination disk. Use with extreme caution.
# Usage: just write-disk-image <image_file> <disk_device>
# Example: just write-disk-image build/qcow2/disk.qcow2 /dev/sdX
write-disk-image disk image='alma' image_tag='latest':
    #!/bin/bash
    set -euo pipefail
    echo "DANGER: This will overwrite all data on {{disk}}".
    echo "You have 5 seconds to press Ctrl+C to cancel."
    sleep 5
    echo "Writing {{image}}:{{image_tag}} to {{disk}}..."
    sudo qemu-img convert -O raw -p ./output/{{image}}/{{image_tag}}/qcow2/disk.qcow2 {{disk}}
    sudo sync -f {{disk}}
    sudo sync {{disk}}
    echo "Write complete."


# ==============================================================================
# Recipes from dev-tools/testvm.sh
# ==============================================================================

# Default variables for the test VM
_VM_MEMORY        := "2048"
_VM_VCPUS         := "2"
_VM_REMOTE_IMAGE  := "ghcr.io/braccae/alma:latest"
_VM_LOCAL_TAG     := "localhost/rhel-test:latest"
_VM_BUILD_DIR     := "output/test-vm"
_VM_DISK_IMAGE    := _VM_BUILD_DIR + "/qcow2/disk.qcow2"

# Check for required dependencies for running a test VM
check-vm-deps:
    #!/bin/bash
    set -euo pipefail
    DEPS=("podman" "virsh" "virt-install" "qemu-img")
    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' not found. Please install it."
            exit 1
        fi
    done
    echo "All VM dependencies found."

# [private] Builds the bootable qcow2 disk image for the test VM.
# This is a helper recipe for the `test-vm` target.
_vm-build-disk image_tag='latest':
    #!/bin/bash
    set -euo pipefail
    echo "--- Building disk image for test VM using tag: {{image_tag}} ---"
    just build-disk-image {{image_tag}}
    
    # Move the built image to the expected test VM location
    sudo mkdir -p "$(dirname '{{_VM_DISK_IMAGE}}')"
    sudo mv "./output/{{image_tag}}/qcow2/disk.qcow2" "{{_VM_DISK_IMAGE}}"

# Build and run an ephemeral test VM.
# The VM is automatically destroyed and cleaned up on exit.
# Usage: just test-vm [image_tag] [memory=2048] [vcpus=2]
# Example (latest tag): just test-vm
# Example (specific tag): just test-vm centos
# Example (more resources): just test-vm latest 4096 4
test-vm image_tag='latest' memory=_VM_MEMORY vcpus=_VM_VCPUS: check-vm-deps ( _vm-build-disk image_tag )
    #!/bin/bash
    set -euo pipefail

    if [[ ! -f "{{_VM_DISK_IMAGE}}" ]]; then
        echo "Error: Disk image not found at {{_VM_DISK_IMAGE}}"
        exit 1
    fi

    VM_NAME="ephemeral-test-$(date +%s)"
    EPHEMERAL_IMAGE="/var/lib/libvirt/images/${VM_NAME}.qcow2"

    cleanup() {
        echo "--- Cleaning up VM: $VM_NAME ---"
        # Check if VM exists before trying to destroy/undefine
        if sudo virsh list --all --name | grep -q "^${VM_NAME}$"; then
            sudo virsh destroy "$VM_NAME" &>/dev/null || true
            sudo virsh undefine "$VM_NAME" --remove-all-storage &>/dev/null || true
            echo "VM destroyed and undefined."
        else
            echo "VM not found, skipping cleanup."
        fi
    }
    trap cleanup EXIT INT TERM

    echo "--- Preparing ephemeral VM image ---"
    # Move the built disk image to the libvirt images directory
    sudo mv "{{_VM_DISK_IMAGE}}" "$EPHEMERAL_IMAGE"
    # The build dir might be left over, remove it.
    sudo rm -rf "$(dirname '{{_VM_DISK_IMAGE}}')"

    echo "--- Creating and starting VM: $VM_NAME ---"
    sudo virt-install \
        --name "$VM_NAME" \
        --memory "{{memory}}" \
        --vcpus "{{vcpus}}" \
        --disk path="$EPHEMERAL_IMAGE",format=qcow2,bus=virtio \
        --import \
        --os-variant=centos-stream9 \
        --network network=default,model=virtio \
        --graphics vnc,listen=0.0.0.0 \
        --console pty,target_type=serial \
        --noautoconsole \
        --boot uefi

    echo "--- Waiting for VM to start... ---"
    sleep infinity # Simple wait, can be improved with a loop

    VNC_DISPLAY=$(sudo virsh vncdisplay "$VM_NAME" 2>/dev/null || echo "Not available")
    echo ""
    echo "================ VM Information ================"
    echo "VM Name:      $VM_NAME"
    echo "VNC Display:  $VNC_DISPLAY (Connect with: vncviewer localhost${VNC_DISPLAY})"
    echo "Console:      run0 virsh console $VM_NAME"
    echo "================================================"
    exit


# ==============================================================================
# 4 Run-Mode Verification Harness (docs/mode-spec.md)
# ==============================================================================

_VM_BOOT_TIMEOUT  := "300"
_APP_STOP_TIMEOUT := "30"
_FAILED_UNITS_ALLOWLIST := "^(cloud-init|cloud-config|cloud-final|systemd-networkd-wait-online|NetworkManager-wait-online)"

# Mode 2 — rootless-systemd: run container with --systemd=always as unprivileged user
# Usage: just test-rootless-systemd [image=localhost/alma:latest]
test-rootless-systemd image='localhost/alma:latest':
    #!/bin/bash
    set -euo pipefail

    MODE="rootless-systemd"
    IMAGE="{{image}}"
    STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    UTC_TS="$(date -u +%Y%m%dT%H%M%SZ)"
    EVID_DIR="output/evidence/${MODE}/${UTC_TS}"
    mkdir -p "$EVID_DIR"

    C1="fail"; C2="fail"; C3="fail"; C4="fail"; C5="fail"; C6="fail"
    CONTAINER_NAME="mode2-systemd"

    write_result() {
        local res="$1"
        local ended
        ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        cat > "$EVID_DIR/result.json" <<EOF
    {
      "mode": "${MODE}",
      "image": "${IMAGE}",
      "started": "${STARTED}",
      "ended": "${ended}",
      "result": "${res}",
      "conditions": {
        "rootless-systemd.1": "${C1}",
        "rootless-systemd.2": "${C2}",
        "rootless-systemd.3": "${C3}",
        "rootless-systemd.4": "${C4}",
        "rootless-systemd.5": "${C5}",
        "rootless-systemd.6": "${C6}"
      }
    }
    EOF
    }

    fail_cond() {
        local cid="$1"
        shift
        write_result "fail"
        echo "FAIL: ${cid} $*"
        exit 1
    }

    cleanup() {
        podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT INT TERM

    # rootless-systemd.6: Unprivileged start + subuid/subgid check
    if [ "$(id -u)" -eq 0 ]; then
        fail_cond "rootless-systemd.6" "invoking UID must not be 0 (rootless mode required)"
    fi
    USER_NAME="$(id -un)"
    if ! grep -q "^${USER_NAME}:" /etc/subuid 2>/dev/null || ! grep -q "^${USER_NAME}:" /etc/subgid 2>/dev/null; then
        fail_cond "rootless-systemd.6" "missing /etc/subuid or /etc/subgid entry for user ${USER_NAME}"
    fi
    C6="pass"

    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    DRI_PRESENT=0
    RUN_ARGS=(-d --name "$CONTAINER_NAME" --systemd=always -p 3000:3000)
    if [ -e /dev/dri ]; then
        DRI_PRESENT=1
        RUN_ARGS+=(--device /dev/dri)
    fi

    if ! podman run "${RUN_ARGS[@]}" "$IMAGE" >/dev/null; then
        fail_cond "rootless-systemd.6" "podman run failed to start ${IMAGE}"
    fi

    # rootless-systemd.1: No privileged flag
    podman inspect "$CONTAINER_NAME" > "$EVID_DIR/podman-inspect.json"
    PRIV_FLAG="$(podman inspect "$CONTAINER_NAME" --format '{{{{.HostConfig.Privileged}}' | tr -d '[:space:]')"
    if [ "$PRIV_FLAG" != "false" ]; then
        fail_cond "rootless-systemd.1" "HostConfig.Privileged is '${PRIV_FLAG}', expected 'false'"
    fi
    C1="pass"

    # rootless-systemd.2: systemd is PID 1
    PID1_COMM="$(podman exec "$CONTAINER_NAME" ps -o comm= -p 1 | tr -d '[:space:]')"
    echo "$PID1_COMM" > "$EVID_DIR/ps-pid1.txt"
    if [ "$PID1_COMM" != "systemd" ]; then
        fail_cond "rootless-systemd.2" "PID 1 comm is '${PID1_COMM}', expected 'systemd'"
    fi
    C2="pass"

    # rootless-systemd.3: systemd reaches a target
    SYS_STATE="$(podman exec "$CONTAINER_NAME" systemctl is-system-running --wait 2>&1 || true)"
    echo "$SYS_STATE" > "$EVID_DIR/systemctl-status.txt"
    SYS_STATE_TRIMMED="$(echo "$SYS_STATE" | tr -d '[:space:]')"
    if [ "$SYS_STATE_TRIMMED" != "running" ] && [ "$SYS_STATE_TRIMMED" != "degraded" ]; then
        fail_cond "rootless-systemd.3" "systemctl is-system-running returned '${SYS_STATE_TRIMMED}'"
    fi
    C3="pass"

    # rootless-systemd.4: No unexpected failed units
    podman exec "$CONTAINER_NAME" systemctl --failed --no-legend > "$EVID_DIR/failed-units.txt" 2>&1 || true
    UNEXPECTED_FAILED="$(grep -Ev '{{_FAILED_UNITS_ALLOWLIST}}' "$EVID_DIR/failed-units.txt" | sed '/^[[:space:]]*$/d' || true)"
    if [ -n "$UNEXPECTED_FAILED" ]; then
        fail_cond "rootless-systemd.4" "unexpected failed units: ${UNEXPECTED_FAILED}"
    fi
    C4="pass"

    # rootless-systemd.5: Exposed port binds (skipped when /dev/dri is absent and port 3000 is down)
    HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ 2>/dev/null || true)"
    echo "$HTTP_CODE" > "$EVID_DIR/port-probe.txt"
    if [[ "$HTTP_CODE" =~ ^(2[0-9]{2}|3[0-9]{2}|401)$ ]]; then
        C5="pass"
    elif [ "$DRI_PRESENT" -eq 0 ]; then
        C5="skipped"
    else
        fail_cond "rootless-systemd.5" "port 3000 probe returned HTTP '${HTTP_CODE}'"
    fi

    write_result "pass"
    echo "PASS: ${MODE} ${IMAGE}"

# Mode 3 — rootless-app: single application container without init or systemd
# Usage: just test-rootless-app [image=localhost/alma:latest] [command="echo ok"]
test-rootless-app image='localhost/alma:latest' command='echo ok':
    #!/bin/bash
    set -euo pipefail

    MODE="rootless-app"
    IMAGE="{{image}}"
    CMD="{{command}}"
    APP_STOP_TIMEOUT="${APP_STOP_TIMEOUT:-{{_APP_STOP_TIMEOUT}}}"
    STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    UTC_TS="$(date -u +%Y%m%dT%H%M%SZ)"
    EVID_DIR="output/evidence/${MODE}/${UTC_TS}"
    mkdir -p "$EVID_DIR"

    C1="fail"; C2="fail"; C3="fail"; C4="fail"
    CONTAINER_NAME="mode3-app"

    write_result() {
        local res="$1"
        local ended
        ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        cat > "$EVID_DIR/result.json" <<EOF
    {
      "mode": "${MODE}",
      "image": "${IMAGE}",
      "started": "${STARTED}",
      "ended": "${ended}",
      "result": "${res}",
      "conditions": {
        "rootless-app.1": "${C1}",
        "rootless-app.2": "${C2}",
        "rootless-app.3": "${C3}",
        "rootless-app.4": "${C4}"
      }
    }
    EOF
    }

    fail_cond() {
        local cid="$1"
        shift
        write_result "fail"
        echo "FAIL: ${cid} $*"
        exit 1
    }

    cleanup() {
        podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT INT TERM

    if [ "$(id -u)" -eq 0 ]; then
        fail_cond "rootless-app.1" "invoking UID must not be 0 (rootless mode required)"
    fi
    USER_NAME="$(id -un)"
    if ! grep -q "^${USER_NAME}:" /etc/subuid 2>/dev/null || ! grep -q "^${USER_NAME}:" /etc/subgid 2>/dev/null; then
        fail_cond "rootless-app.1" "missing /etc/subuid or /etc/subgid entry for user ${USER_NAME}"
    fi

    # rootless-app.2 & rootless-app.4: Smoke command clean exit + log streaming
    set +e
    podman run --rm "$IMAGE" $CMD > "$EVID_DIR/logs.txt" 2>&1
    SMOKE_RC=$?
    set -e
    echo "exit=${SMOKE_RC}" > "$EVID_DIR/smoke-exit.txt"
    if [ "$SMOKE_RC" -ne 0 ]; then
        fail_cond "rootless-app.2" "smoke command exited with ${SMOKE_RC}"
    fi
    C2="pass"

    if [ ! -s "$EVID_DIR/logs.txt" ]; then
        fail_cond "rootless-app.4" "logs.txt is empty; command stdout/stderr did not stream"
    fi
    C4="pass"

    # rootless-app.1 & rootless-app.3: Long-running command, PID 1 check, and SIGTERM handling
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    podman run --rm --name "$CONTAINER_NAME" -d "$IMAGE" sleep 300 >/dev/null

    PID1_COMM="$(podman exec "$CONTAINER_NAME" ps -o comm= -p 1 2>/dev/null | tr -d '[:space:]' || true)"
    echo "$PID1_COMM" > "$EVID_DIR/pid1.txt"
    if [ -z "$PID1_COMM" ] || [ "$PID1_COMM" = "systemd" ] || [ "$PID1_COMM" = "init" ] || [ "$PID1_COMM" = "/sbin/init" ]; then
        fail_cond "rootless-app.1" "PID 1 comm is '${PID1_COMM}', expected direct command (not systemd/init)"
    fi
    C1="pass"

    podman kill --signal SIGTERM "$CONTAINER_NAME" >/dev/null
    set +e
    SIG_EXIT="$(timeout "${APP_STOP_TIMEOUT}" podman wait "$CONTAINER_NAME" 2>/dev/null | tr -d '[:space:]')"
    WAIT_RC=$?
    set -e
    echo "exit=${SIG_EXIT:-$WAIT_RC}" > "$EVID_DIR/signal-exit.txt"
    if [ "$WAIT_RC" -ne 0 ] || { [ "$SIG_EXIT" != "0" ] && [ "$SIG_EXIT" != "143" ]; }; then
        fail_cond "rootless-app.3" "SIGTERM wait_rc=${WAIT_RC} exit='${SIG_EXIT}', expected 0 or 143 within ${APP_STOP_TIMEOUT}s"
    fi
    C3="pass"

    write_result "pass"
    echo "PASS: ${MODE} ${IMAGE}"

# Mode 4 — rootless-multi: multi-process container with userns and fuse-overlayfs
# Usage: just test-rootless-multi [image=localhost/alma:latest]
test-rootless-multi image='localhost/alma:latest':
    #!/bin/bash
    set -euo pipefail

    MODE="rootless-multi"
    IMAGE="{{image}}"
    STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    UTC_TS="$(date -u +%Y%m%dT%H%M%SZ)"
    EVID_DIR="output/evidence/${MODE}/${UTC_TS}"
    mkdir -p "$EVID_DIR"

    C1="fail"; C2="fail"; C3="fail"; C4="fail"; C5="fail"
    CONTAINER_NAME="mode4-multi"

    write_result() {
        local res="$1"
        local ended
        ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        cat > "$EVID_DIR/result.json" <<EOF
    {
      "mode": "${MODE}",
      "image": "${IMAGE}",
      "started": "${STARTED}",
      "ended": "${ended}",
      "result": "${res}",
      "conditions": {
        "rootless-multi.1": "${C1}",
        "rootless-multi.2": "${C2}",
        "rootless-multi.3": "${C3}",
        "rootless-multi.4": "${C4}",
        "rootless-multi.5": "${C5}"
      }
    }
    EOF
    }

    fail_cond() {
        local cid="$1"
        shift
        write_result "fail"
        echo "FAIL: ${cid} $*"
        exit 1
    }

    cleanup() {
        podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT INT TERM

    if [ "$(id -u)" -eq 0 ]; then
        fail_cond "rootless-multi.2" "invoking UID must not be 0 (rootless mode required)"
    fi
    USER_NAME="$(id -un)"
    USER_UID="$(id -u)"

    # rootless-multi.2: Subuid/subgid present for invoking user
    if ! grep -q "^${USER_NAME}:" /etc/subuid 2>/dev/null || ! grep -q "^${USER_NAME}:" /etc/subgid 2>/dev/null; then
        fail_cond "rootless-multi.2" "missing /etc/subuid or /etc/subgid entry for user ${USER_NAME}"
    fi
    C2="pass"

    if [ ! -e /dev/fuse ]; then
        fail_cond "rootless-multi.1" "/dev/fuse is absent on host"
    fi

    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    podman run -d \
        --name "$CONTAINER_NAME" \
        --systemd=always \
        --device /dev/fuse \
        "$IMAGE" >/dev/null

    podman exec "$CONTAINER_NAME" systemctl is-system-running --wait >/dev/null 2>&1 || true
    podman exec "$CONTAINER_NAME" /usr/sbin/setup-podman-user "$USER_NAME" "$USER_UID" > "$EVID_DIR/setup-podman-user.log" 2>&1 || true

    # rootless-multi.1: fuse-overlayfs storage
    podman exec "$CONTAINER_NAME" sh -c 'podman info --format "{{{{.Store.GraphDriverName}}"' > "$EVID_DIR/podman-info.txt" 2>&1 || true
    podman exec "$CONTAINER_NAME" sh -c 'mount | grep fuse-overlayfs || true' > "$EVID_DIR/mount.txt" 2>&1 || true
    GRAPH_DRIVER="$(tr -d '[:space:]' < "$EVID_DIR/podman-info.txt")"
    if [ "$GRAPH_DRIVER" != "fuse-overlayfs" ] || grep -qi "operation not permitted" "$EVID_DIR/mount.txt"; then
        fail_cond "rootless-multi.1" "graph driver is '${GRAPH_DRIVER}' (expected 'fuse-overlayfs') or mount error"
    fi
    C1="pass"

    # rootless-multi.3: Nested container runs
    set +e
    podman exec "$CONTAINER_NAME" sh -c "podman run --rm ${IMAGE} echo nested-ok" > "$EVID_DIR/nested-run.txt" 2>&1
    NESTED_RC=$?
    set -e
    if [ "$NESTED_RC" -ne 0 ] || ! grep -q "nested-ok" "$EVID_DIR/nested-run.txt"; then
        fail_cond "rootless-multi.3" "nested container run failed (rc=${NESTED_RC})"
    fi
    C3="pass"

    # rootless-multi.4: User lingering
    podman exec "$CONTAINER_NAME" loginctl show-user "$USER_NAME" -P Linger > "$EVID_DIR/linger.txt" 2>&1 || true
    LINGER_VAL="$(tr -d '[:space:]' < "$EVID_DIR/linger.txt")"
    if [ "$LINGER_VAL" != "yes" ]; then
        fail_cond "rootless-multi.4" "linger for ${USER_NAME} is '${LINGER_VAL}', expected 'yes'"
    fi
    C4="pass"

    # rootless-multi.5: Concurrent user services
    podman exec "$CONTAINER_NAME" sh -c "run0 -u ${USER_NAME} systemctl --user is-active podman-auto-update.timer" > "$EVID_DIR/quadlet-units.txt" 2>&1 || \
        podman exec "$CONTAINER_NAME" sh -c 'systemctl --user is-active podman-auto-update.timer' > "$EVID_DIR/quadlet-units.txt" 2>&1 || true
    QUADLET_STATE="$(tr -d '[:space:]' < "$EVID_DIR/quadlet-units.txt")"
    if [ "$QUADLET_STATE" != "active" ]; then
        fail_cond "rootless-multi.5" "podman-auto-update.timer state is '${QUADLET_STATE}', expected 'active'"
    fi
    C5="pass"

    write_result "pass"
    echo "PASS: ${MODE} ${IMAGE}"

# Mode 1 — bootc-vm: full OS UEFI boot and SSH verification in libvirt/QEMU
# Usage: just test-vm-bootc [image=alma] [tag=latest] [memory=2048] [vcpus=2]
test-vm-bootc image='alma' tag='latest' memory=_VM_MEMORY vcpus=_VM_VCPUS: check-vm-deps
    #!/bin/bash
    set -euo pipefail

    MODE="bootc-vm"
    IMAGE_REF="{{image}}:{{tag}}"
    VM_BOOT_TIMEOUT="${VM_BOOT_TIMEOUT:-{{_VM_BOOT_TIMEOUT}}}"
    STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    UTC_TS="$(date -u +%Y%m%dT%H%M%SZ)"
    EVID_DIR="output/evidence/${MODE}/${UTC_TS}"
    mkdir -p "$EVID_DIR"

    C1="fail"; C2="fail"; C3="fail"; C4="fail"; C5="fail"; C6="fail"; C7="fail"

    write_result() {
        local res="$1"
        local ended
        ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        cat > "$EVID_DIR/result.json" <<EOF
    {
      "mode": "${MODE}",
      "image": "${IMAGE_REF}",
      "started": "${STARTED}",
      "ended": "${ended}",
      "result": "${res}",
      "conditions": {
        "bootc-vm.1": "${C1}",
        "bootc-vm.2": "${C2}",
        "bootc-vm.3": "${C3}",
        "bootc-vm.4": "${C4}",
        "bootc-vm.5": "${C5}",
        "bootc-vm.6": "${C6}",
        "bootc-vm.7": "${C7}"
      }
    }
    EOF
    }

    fail_cond() {
        local cid="$1"
        shift
        write_result "fail"
        echo "FAIL: ${cid} $*"
        exit 1
    }

    DISK_SRC="./output/{{image}}/{{tag}}/qcow2/disk.qcow2"
    if [ ! -f "$DISK_SRC" ]; then
        just build-disk-image "{{image}}" "{{tag}}"
    fi
    if [ ! -f "$DISK_SRC" ]; then
        fail_cond "bootc-vm.1" "disk image not found at ${DISK_SRC}"
    fi

    VM_NAME="bootc-vm-{{image}}-$(date +%s)"
    EPHEMERAL_IMAGE="/var/lib/libvirt/images/${VM_NAME}.qcow2"
    RAW_SERIAL_LOG="/var/lib/libvirt/images/${VM_NAME}-serial.log"

    cleanup() {
        if [ -f "$RAW_SERIAL_LOG" ]; then
            sudo cp "$RAW_SERIAL_LOG" "$EVID_DIR/serial.log" 2>/dev/null || true
            sudo chown "$(id -u):$(id -g)" "$EVID_DIR/serial.log" 2>/dev/null || true
        fi
        if sudo virsh list --all --name 2>/dev/null | grep -q "^${VM_NAME}$"; then
            sudo virsh destroy "$VM_NAME" &>/dev/null || true
            sudo virsh undefine "$VM_NAME" --remove-all-storage --nvram &>/dev/null || \
                sudo virsh undefine "$VM_NAME" --remove-all-storage &>/dev/null || true
        fi
        sudo rm -f "$EPHEMERAL_IMAGE" "$RAW_SERIAL_LOG" 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    sudo cp "$DISK_SRC" "$EPHEMERAL_IMAGE"
    sudo touch "$RAW_SERIAL_LOG"
    sudo chmod 666 "$RAW_SERIAL_LOG"

    SSH_KEY="${SSH_IDENTITY_FILE:-$HOME/.ssh/id_ed25519}"
    CLOUD_INIT_ARGS=()
    if [ ! -f "$SSH_KEY" ]; then
        SSH_KEY="$EVID_DIR/id_ed25519"
        ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" >/dev/null
        USER_DATA="$EVID_DIR/user-data"
        cat > "$USER_DATA" <<EOF
    #cloud-config
    users:
      - name: core
        ssh_authorized_keys:
          - $(cat "${SSH_KEY}.pub")
    EOF
        CLOUD_INIT_ARGS=(--cloud-init "user-data=${USER_DATA}")
    fi

    sudo virt-install \
        --name "$VM_NAME" \
        --memory "{{memory}}" \
        --vcpus "{{vcpus}}" \
        --disk path="$EPHEMERAL_IMAGE",format=qcow2,bus=virtio \
        --import \
        --os-variant=centos-stream9 \
        --network network=default,model=virtio \
        --graphics none \
        --serial "file,path=${RAW_SERIAL_LOG}" \
        --console pty,target_type=serial \
        --noautoconsole \
        --boot uefi \
        "${CLOUD_INIT_ARGS[@]}"

    SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
    DEADLINE=$((SECONDS + VM_BOOT_TIMEOUT))
    VM_IP=""
    SSH_OK=0

    while [ "$SECONDS" -lt "$DEADLINE" ]; do
        VM_IP="$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | awk '/ipv4/ {split($4, a, "/"); print a[1]; exit}' || true)"
        if [ -n "$VM_IP" ]; then
            if ssh "${SSH_OPTS[@]}" "core@${VM_IP}" true >/dev/null 2>&1; then
                SSH_OK=1
                break
            fi
        fi
        sleep 3
    done

    sudo cp "$RAW_SERIAL_LOG" "$EVID_DIR/serial.log" 2>/dev/null || touch "$EVID_DIR/serial.log"
    sudo chown "$(id -u):$(id -g)" "$EVID_DIR/serial.log" 2>/dev/null || true

    # bootc-vm.1: UEFI boot to login (no Kernel panic)
    if [ ! -s "$EVID_DIR/serial.log" ] || grep -qi "Kernel panic" "$EVID_DIR/serial.log"; then
        fail_cond "bootc-vm.1" "serial log missing or Kernel panic detected"
    fi
    C1="pass"

    # bootc-vm.4: Console reachable (login: prompt on serial console)
    if ! grep -q "login:" "$EVID_DIR/serial.log"; then
        fail_cond "bootc-vm.4" "no 'login:' prompt found in serial.log"
    fi
    C4="pass"

    # bootc-vm.5: Network + SSH
    if [ "$SSH_OK" -ne 1 ] || [ -z "$VM_IP" ]; then
        fail_cond "bootc-vm.5" "SSH login to core@${VM_IP:-<no-ip>} timed out after ${VM_BOOT_TIMEOUT}s"
    fi
    ssh "${SSH_OPTS[@]}" "core@${VM_IP}" "ip -4 addr show" > "$EVID_DIR/ip-addr.txt" 2>&1 || true
    if ! grep -q "inet " "$EVID_DIR/ip-addr.txt"; then
        fail_cond "bootc-vm.5" "no IPv4 address found in ip-addr.txt"
    fi
    C5="pass"

    # bootc-vm.2: System target reached
    SYS_STATE="$(ssh "${SSH_OPTS[@]}" "core@${VM_IP}" "systemctl is-system-running --wait" 2>&1 || true)"
    echo "$SYS_STATE" > "$EVID_DIR/systemctl-status.txt"
    SYS_STATE_TRIMMED="$(echo "$SYS_STATE" | tr -d '[:space:]')"
    if [ "$SYS_STATE_TRIMMED" != "running" ] && [ "$SYS_STATE_TRIMMED" != "degraded" ]; then
        fail_cond "bootc-vm.2" "systemctl is-system-running returned '${SYS_STATE_TRIMMED}'"
    fi
    C2="pass"

    # bootc-vm.3: No failed units
    ssh "${SSH_OPTS[@]}" "core@${VM_IP}" "systemctl --failed --no-legend" > "$EVID_DIR/failed-units.txt" 2>&1 || true
    UNEXPECTED_FAILED="$(grep -Ev '{{_FAILED_UNITS_ALLOWLIST}}' "$EVID_DIR/failed-units.txt" | sed '/^[[:space:]]*$/d' || true)"
    if [ -n "$UNEXPECTED_FAILED" ]; then
        fail_cond "bootc-vm.3" "unexpected failed units: ${UNEXPECTED_FAILED}"
    fi
    C3="pass"

    # bootc-vm.6: bootc status clean
    if ! ssh "${SSH_OPTS[@]}" "core@${VM_IP}" "sudo bootc status --json" > "$EVID_DIR/bootc-status.json" 2>&1; then
        fail_cond "bootc-vm.6" "bootc status --json exited non-zero"
    fi
    if ! python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d.get("status", {}).get("booted") is not None' "$EVID_DIR/bootc-status.json" >/dev/null 2>&1; then
        fail_cond "bootc-vm.6" "bootc-status.json invalid or missing booted deployment"
    fi
    C6="pass"

    # bootc-vm.7: kmods loaded (ZFS images only; skipped for non-kmod images)
    ssh "${SSH_OPTS[@]}" "core@${VM_IP}" "lsmod | grep -c zfs || true" > "$EVID_DIR/lsmod-zfs.txt" 2>&1 || true
    if [[ "{{image}}" =~ ^(laptop|webtop)$ ]]; then
        C7="skipped"
    else
        ZFS_COUNT="$(tr -d '[:space:]' < "$EVID_DIR/lsmod-zfs.txt")"
        if [ -z "$ZFS_COUNT" ] || [ "$ZFS_COUNT" -lt 1 ] 2>/dev/null; then
            fail_cond "bootc-vm.7" "lsmod zfs count is '${ZFS_COUNT}', expected >= 1"
        fi
        C7="pass"
    fi

    write_result "pass"
    echo "PASS: ${MODE} ${IMAGE_REF}"