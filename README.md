# CoreOS Custom Images Project

These are my custom bootc-based container images tailored for different infrastructure use cases, including hyperconverged infrastructure (HCI), workstations, development environments, and specialized workloads.

## Overview

This project builds upon bootc-compatible base images to create customized, immutable operating system images with pre-configured software stacks. The images are designed for modern container-native infrastructure with automatic updates and declarative configuration.

## Available Images

### 1. Base AlmaLinux bootc (`Containerfile`)
- **Base**: AlmaLinux bootc 10
- **Purpose**: General-purpose server image
- **Key Features**:
  - Tailscale VPN integration
  - Cockpit plugins for a remote cockpit-ws instance
  - Backup tools (borgmatic, rclone, rsync)
  - QEMU guest agent for virtualization
  - Firewall and security tools

### 2. HCI Variant (`hci.Containerfile`)
- **Purpose**: Hyperconverged Infrastructure
- **Key Features**:
  - Complete QEMU/KVM virtualization stack
  - Cockpit Machines for VM management
  - File sharing capabilities
  - Comprehensive virtualization device support



### 5. Webtop (`webtop.Containerfile`)
- **Purpose**: Desktop environment in container
#### Currently on hold due to upstream fedora removing x11
(EXPERIMENTAL: Linuxserverio style webtop with kasmVNC using systemd and podman instead of s6)

## Project Structure

```
├── Containerfile              # Main AlmaLinux bootc image
├── hci.Containerfile         # HCI image (AlmaLinux-based)
├── workstation.Containerfile # Workstation image (Bazzite-based)
├── laptop.Containerfile      # Laptop image (Bazzite-based)
├── dockerhost.Containerfile  # Docker Host image
├── webtop.Containerfile      # Desktop environment in container
├── rootfs/                   # Filesystem overlays
│   ├── btrfs_config/        # Btrfs-specific configurations
│   ├── common/              # Shared configurations
│   ├── hci/                 # HCI-specific files
│   ├── workstation/         # Workstation-specific files
│   └── webtop/              # Desktop environment files
├── build/                    # Build artifacts
├── scripts/                  # Build and deployment scripts
└── .github/                  # CI/CD workflows
```

## Key Features

### Security & Networking
- **Tailscale**: Zero-config VPN mesh networking
- **Firewalld**: Advanced firewall management
- **SSH**: Ed25519 key authentication for `core` user

### Management & Monitoring
- **Cockpit**: Web-based system administration
  - Network management
  - Container/Podman integration
  - OSTree/bootc updates
  - SELinux management
  - Storage management
  - File management

### Backup & Storage
- **Borgmatic**: Automated, deduplicated backups
- **Rclone**: Cloud storage synchronization
- **ZFS**: Advanced filesystem with snapshots (HCI images)
- **Btrfs**: Copy-on-write filesystem support

### Virtualization (HCI Images)
- **QEMU/KVM**: Full virtualization stack
- **Cockpit Machines**: VM management interface
- **Multiple architectures**: x86, ARM, RISC-V support
- **GPU passthrough**: Virtio-GPU support

## Getting Started

### Prerequisites
- Container runtime (Podman/Docker)
- bootc-compatible system for deployment

### Building Images

```bash
# Build base AlmaLinux image
podman build -f Containerfile -t my-alma:latest .

# Build HCI image
podman build -f hci.Containerfile -t my-hci:latest .
```

### Deployment

#### Using bootc
```bash
# Switch to custom image
sudo bootc switch ghcr.io/yourusername/your-image:latest
sudo systemctl reboot
```

### Configuration

#### User Configuration (`config.toml`)
- Default user: `core`
- SSH key authentication
- Wheel group membership for sudo access
- Minimum root filesystem: 48 GiB

## Development
### Adding Custom Configurations
1. Place files in appropriate `rootfs/` subdirectory
2. Update relevant Containerfile to copy files
3. Enable systemd services as needed

### Testing
```bash
# Lint container before deployment
bootc container lint
```

## Services & Integrations

### Enabled Services
- `qemu-guest-agent`: VM integration
- `tailscaled`: VPN mesh networking

### Web Interfaces
- **Cockpit**: `https://your-host:9090` (only on hci images)

## Security Considerations

- Images use immutable, atomic updates via bootc/OSTree
- SSH key-only authentication (no password login)
- Firewall enabled by default
- SELinux enforcing mode
- Regular security updates through base image updates

## Contributing

1. Fork the repository
2. Create feature branch
3. Test changes with `bootc container lint` and `dev-tools/testvm.sh`
4. Submit pull request
