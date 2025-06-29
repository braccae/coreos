#!/bin/bash

set -euo pipefail

# Configuration
IMAGE_NAME="centos-test"
VM_NAME="ephemeral-${IMAGE_NAME}-$(date +%s)"
MEMORY="2048"  # MB
VCPUS="2"
VNC_PORT="5900"
CONTAINERFILE=""  # Path to Containerfile for local builds
LOCAL_IMAGE_TAG="localhost/coreos-test:latest"  # Tag for locally built images
REMOTE_IMAGE="ghcr.io/braccae/coreos:centos"  # Default remote image

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log "Cleaning up ephemeral VM..."
    if virsh list --all 2>/dev/null | grep -q "$VM_NAME"; then
        log "Destroying VM: $VM_NAME"
        virsh destroy "$VM_NAME" 2>/dev/null || true
        virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    fi
    # Clean up the ephemeral disk image
    if [[ -f "/var/lib/libvirt/images/${VM_NAME}.qcow2" ]]; then
        rm -f "/var/lib/libvirt/images/${VM_NAME}.qcow2"
        log "Removed ephemeral disk image"
    fi
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

check_dependencies() {
    local deps=("podman" "virsh" "virt-install" "qemu-img")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' not found. Please install it."
            exit 1
        fi
    done
}

check_permissions() {
    # Check if running as root or with appropriate permissions
    if [[ $EUID -ne 0 ]] && ! groups | grep -q libvirt; then
        error "This script requires root privileges or membership in the 'libvirt' group"
        error "To add your user to the libvirt group, run: sudo usermod -a -G libvirt \$USER"
        error "Then log out and log back in for the changes to take effect"
        exit 1
    fi

    # Check if libvirt is running
    # if ! systemctl is-active --quiet libvirtd; then
    #     error "libvirtd service is not running. Start it with: sudo systemctl start libvirtd"
    #     exit 1
    # fi

    # Check if we can write to libvirt images directory
    if [[ ! -w "/var/lib/libvirt/images" ]]; then
        error "Cannot write to /var/lib/libvirt/images directory"
        exit 1
    fi
}

build_local_image() {
    local containerfile="$1"

    log "Building local container image from $containerfile..."

    # Check if Containerfile exists
    if [[ ! -f "$containerfile" ]]; then
        error "Containerfile not found: $containerfile"
        exit 1
    fi

    # Get the directory containing the Containerfile for build context
    local build_context
    build_context=$(dirname "$containerfile")
    local containerfile_name
    containerfile_name=$(basename "$containerfile")

    # Build the image
    log "Building image with tag: $LOCAL_IMAGE_TAG"
    if ! podman build \
        --file "$containerfile" \
        --tag "$LOCAL_IMAGE_TAG" \
        "$build_context"; then
        error "Failed to build local container image"
        exit 1
    fi

    log "Local container image built successfully: $LOCAL_IMAGE_TAG"
}

build_image() {
    local image_to_use

    if [[ -n "$CONTAINERFILE" ]]; then
        # Build local image first
        build_local_image "$CONTAINERFILE"
        image_to_use="$LOCAL_IMAGE_TAG"
        log "Using locally built image: $image_to_use"
    else
        # Use remote image
        image_to_use="$REMOTE_IMAGE"
        log "Using remote image: $image_to_use"
        log "Pulling bootc image..."
        podman pull "$image_to_use"
    fi

    log "Building bootc disk image..."

    # Ensure build directory exists
    mkdir -p build

    podman run \
        --rm \
        -it \
        --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        -v ./config.toml:/config.toml:ro \
        -v ./build:/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 \
        --use-librepo=True \
        --rootfs xfs \
        "$image_to_use"

    if [[ ! -f "build/qcow2/disk.qcow2" ]]; then
        error "Build failed - disk image not found at build/qcow2/disk.qcow2"
        exit 1
    fi

    log "Disk image built successfully"
}

prepare_vm_image() {
    log "Preparing ephemeral VM image..."

    # Create a copy of the built image for the ephemeral VM
    mv "build/qcow2/disk.qcow2" "/var/lib/libvirt/images/${VM_NAME}.qcow2"

    # Also save the original to the standard location for future reuse
    # cp "build/qcow2/disk.qcow2" "/var/lib/libvirt/images/centos-test.qcow2"

    log "Ephemeral VM image prepared: /var/lib/libvirt/images/${VM_NAME}.qcow2"
    log "Base image saved: /var/lib/libvirt/images/centos-test.qcow2"
}

create_vm() {
    log "Creating ephemeral VM: $VM_NAME"

    # Check if VNC port is available
    if netstat -tln 2>/dev/null | grep -q ":${VNC_PORT} " || ss -tln 2>/dev/null | grep -q ":${VNC_PORT} "; then
        warn "VNC port $VNC_PORT is in use, letting libvirt choose automatically"
        VNC_OPTION="vnc,listen=0.0.0.0"
    else
        VNC_OPTION="vnc,listen=0.0.0.0,port=${VNC_PORT}"
    fi

    virt-install \
        --name "$VM_NAME" \
        --memory "$MEMORY" \
        --vcpus "$VCPUS" \
        --disk path="/var/lib/libvirt/images/${VM_NAME}.qcow2",format=qcow2,bus=virtio \
        --import \
        --os-variant=centos-stream9 \
        --network network=default,model=virtio \
        --graphics "$VNC_OPTION" \
        --console pty,target_type=serial \
        --noautoconsole \
        --boot uefi

    if [[ $? -ne 0 ]]; then
        error "Failed to create VM"
        exit 1
    fi

    log "VM created successfully"
}

wait_for_vm() {
    log "Waiting for VM to start..."
    local timeout=30
    local count=0

    while [[ $count -lt $timeout ]]; do
        if virsh domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
            log "VM is running"
            return 0
        fi
        sleep 2
        ((count += 2))
    done

    warn "VM may not have started properly"
    return 1
}

show_vm_info() {
    # Wait a moment for VM to initialize
    sleep 3

    local vnc_display=$(virsh vncdisplay "$VM_NAME" 2>/dev/null || echo "Not available")
    local vm_state=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "Unknown")

    echo ""
    log "=== VM Information ==="
    echo "VM Name: $VM_NAME"
    echo "Status: $vm_state"
    echo "VNC Display: $vnc_display"
    echo "Memory: ${MEMORY}MB"
    echo "vCPUs: $VCPUS"
    if [[ -n "$CONTAINERFILE" ]]; then
        echo "Built from: $CONTAINERFILE"
        echo "Image: $LOCAL_IMAGE_TAG"
    else
        echo "Image: $REMOTE_IMAGE"
    fi
    echo ""
    log "=== Connection Options ==="
    echo "Console: virsh console $VM_NAME"
    if [[ "$vnc_display" != "Not available" ]]; then
        echo "VNC: vncviewer localhost$vnc_display"
    fi
    echo ""
    log "=== Management Commands ==="
    echo "VM status: virsh domstate $VM_NAME"
    echo "Shutdown: virsh shutdown $VM_NAME"
    echo "Force stop: virsh destroy $VM_NAME"
    echo "VM info: virsh dominfo $VM_NAME"
    echo ""
}

connect_console() {
    log "Connecting to VM console..."
    log "Press Ctrl+] to disconnect from console"
    sleep 2
    virsh console "$VM_NAME"
}

show_help() {
    echo "Usage: $0 [CONTAINERFILE] [OPTIONS]"
    echo ""
    echo "This script builds a bootc image and spins up an ephemeral KVM machine."
    echo "The VM is automatically cleaned up when the script exits."
    echo ""
    echo "Arguments:"
    echo "  CONTAINERFILE          Path to Containerfile for local build (optional)"
    echo "                         If not provided, uses remote image: $REMOTE_IMAGE"
    echo ""
    echo "Options:"
    echo "  --memory MB            Set VM memory in MB (default: 2048)"
    echo "  --vcpus N              Set number of vCPUs (default: 2)"
    echo "  --vnc-port PORT        Set VNC port (default: 5900)"
    echo "  --vm-name NAME         Set custom VM name (default: ephemeral-centos-test-TIMESTAMP)"
    echo "  --no-console           Don't prompt for console connection"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Prerequisites:"
    echo "  - podman, virsh, virt-install, qemu-img must be installed"
    echo "  - libvirtd service must be running"
    echo "  - User must be in 'libvirt' group or run as root"
    echo "  - config.toml file must exist in current directory"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build and run with remote image"
    echo "  $0 centos.Containerfile               # Build from local Containerfile"
    echo "  $0 ./custom.Containerfile --memory 4096  # Local build with more memory"
    echo "  $0 --memory 4096 --vcpus 4            # Remote image with more resources"
    echo "  $0 --no-console                      # Run without console prompt"
}

main() {
    log "Starting ephemeral VM creation process..."

    if [[ -n "$CONTAINERFILE" ]]; then
        log "Will build from local Containerfile: $CONTAINERFILE"
    else
        log "Will use remote image: $REMOTE_IMAGE"
    fi

    check_permissions
    check_dependencies
    build_image
    prepare_vm_image
    create_vm
    wait_for_vm
    show_vm_info

    # Ask user if they want to connect to console
    if [[ "${NO_CONSOLE:-}" != "1" ]]; then
        echo -n "Connect to VM console now? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            connect_console
        else
            log "VM is running. Use the commands above to interact with it."
            log "The VM will be automatically cleaned up when this script exits."
            echo ""
            echo "Press Enter to shutdown and cleanup the VM..."
            read -r
        fi
    else
        log "VM is running in background. The VM will be automatically cleaned up when this script exits."
        echo "Press Enter to shutdown and cleanup the VM..."
        read -r
    fi
}

# Parse positional arguments first
if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]] && [[ "$1" != "-h" ]]; then
    CONTAINERFILE="$1"
    shift
fi

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --vcpus)
            VCPUS="$2"
            shift 2
            ;;
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        --no-console)
            NO_CONSOLE=1
            shift
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            error "Use --help for usage information"
            exit 1
            ;;
    esac
done

main "$@"
