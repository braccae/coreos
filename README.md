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
  - Backup tools (Restic, Databasus, rclone, rsync)
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
- **Purpose**: Fully-featured Fedora KDE desktop environment inside a systemd-managed container
- **Key Features**:
  - **Selkies (Pixelflux Wayland)** for high-performance WebRTC streaming on port 3000
  - Runs **systemd** inside the container as PID 1 to orchestrate desktop and portal services cleanly
  - Fully supports running in completely **unprivileged (non-privileged) mode** by stripping capabilities to bypass the kernel's `no_new_privs` restriction
  - Out-of-the-box support for AMD/Intel GPU hardware acceleration passthrough

> [!WARNING]
> **EXPERIMENTAL**: The Webtop container is highly experimental. Many full desktop systems and applications do not currently function as expected. Specifically, launching **Steam**, deep desktop-container **networking**, and the **Software Center / Bazaar (Discover/flatpaks)** are currently unsupported and do not work.

### 6. Workstation (Alma) (`workstation-alma.Containerfile`)
- **Base**: AlmaLinux bootc 10 (`ghcr.io/braccae/alma:latest`)
- **Purpose**: Bare-bones KDE Plasma 6 GUI base for derived workstation variants — the AlmaLinux GUI base layer, not a full application bundle.
- **Key Features**:
  - Full KDE Plasma Workspaces environment from EPEL: Plasma, KWin, Plasma Login Manager (Wayland), Dolphin, Dolphin plugins, Konsole, Ark, Spectacle, KWrite, System Settings, and Discover
  - Flatpak + Discover Flatpak backend, with a system-wide Flathub remote baked into `/etc/flatpak/remotes.d/`
  - Konqueror as the native KDE browser
  - Hardware/filesystem/codec support that cannot come from Flatpak or AppImage: Intel VA-API, Mesa/Vulkan, full firmware breadth (`amd-gpu-firmware`, `intel-gpu-firmware`, `nvidia-gpu-firmware`, Intel Wi-Fi/USB-Wi-Fi/WWAN/DVB/camera firmware), dual-vendor CPU microcode (`microcode_ctl` + `amd-ucode-firmware`), ALSA UCM/SOF firmware, exFAT/NTFS/APFS (read-only) userspace drivers, MTP, Apple iOS device support, CUPS driverless printing and SANE/airscan scanning, and Samba/CIFS clients
  - Networking and mobile hardware: `NetworkManager-wifi`/`-bluetooth`/`-wwan` plugins, `wpa_supplicant`, `wireless-regdb`, and `ModemManager`
  - Laptop hardware: fingerprint (`fprintd` + `authselect with-fingerprint`), IIO sensors, Wacom, Thunderbolt (`bolt`), smartcards (`pcsc-lite`/`opensc`), camera tooling (`v4l-utils`, `libcamera-tools`), and `smartmontools`
  - KIO integration: Google Drive, MTP, SMB, NFS, SFTP, and AFC via `kio-extras`
  - Zeroconf/mDNS via `kdnssd`, Avahi, and `nss-mdns`
  - Game-controller support: in-kernel PS3/PS4, Wii, Logitech, and generic joysticks, plus ELRepo `kmod-game-controllers` for Xbox, PS5, and Switch via weak-modules
  - `waypipe` for remote applications
  - ZFS kernel modules inherited from the AlmaLinux base image
- **Not included**: browsers other than Konqueror, office suites, KDE PIM/multimedia application groups, developer tooling, virtualization, and gaming stacks. Install applications via Flatpak/AppImage, run containerised tooling through the bundled `distrobox`/`toolbox`, or build a derived variant (`workstation-dx`, gaming, webtop).
- **Notes**: Gearlever is Flathub-only (`it.mijorus.gearlever`); install it from Discover or with `flatpak install flathub it.mijorus.gearlever`. HFS+ and write-capable APFS are not available in EL10; AMD VA-API (`mesa-va-drivers`) is not packaged for x86_64 EL10, so host-side AMD video decode is unavailable (Flatpak runtimes still provide it). CPU microcode for both Intel and AMD is embedded in the initramfs at build time. CUPS, Avahi, `tuned-ppd`, ModemManager, and `pcscd` sockets are enabled, mDNS is allowed in the public firewalld zone for printer/scanner discovery, and fingerprint login is preconfigured via `authselect enable-feature with-fingerprint`. Xbox, PS5, and Switch controllers are provided by ELRepo's `kmod-game-controllers` and linked into the image kernel through weak-modules.

## Project Structure

```
├── Containerfile              # Main AlmaLinux bootc image
├── hci.Containerfile         # HCI image (AlmaLinux-based)
├── workstation.Containerfile # Workstation image (Bazzite-based)
├── workstation-alma.Containerfile # Workstation image (AlmaLinux-based)
├── laptop.Containerfile      # Laptop image (Bazzite-based)
├── dockerhost.Containerfile  # Docker Host image
├── webtop.Containerfile      # Desktop environment in container
├── rootfs/                   # Filesystem overlays
│   ├── btrfs_config/        # Btrfs-specific configurations
│   ├── common/              # Shared configurations
│   ├── hci/                 # HCI-specific files
│   ├── workstation/         # Workstation-specific files
│   ├── workstation-alma/    # AlmaLinux workstation overlay (Flathub remote, ZRAM, polkit)
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
- **Restic & Databasus**: Automated, deduplicated file and database backups
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

# Build Webtop image
podman build -f webtop.Containerfile -t fedora-webtop:latest .

# Build Workstation (Alma) image
podman build -f workstation-alma.Containerfile -t localhost/workstation-alma:latest .
```

### Running the Webtop Container

#### 1. Direct Podman CLI (Unprivileged & Secure)
You can run the container securely without the `--privileged` flag by passing `--systemd=always` and mapping the GPU device:

```bash
podman run -d \
  --name webtop-run \
  --systemd=always \
  --device /dev/dri \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --security-opt unmask=all \
  --volume webtop-home:/home/webtop \
  --volume webtop-flatpak:/var/lib/flatpak \
  -p 3000:3000 \
  localhost/fedora-webtop:latest
```

`/dev/dri` enables hardware capture/encode (omit it for software rendering).
`/dev/fuse` + `SYS_ADMIN` + `seccomp=unconfined` + `label=disable` +
`unmask=all` are required for Flatpak and FUSE AppImages. See [docs/webtop.md](docs/webtop.md) for GPU passthrough, Flatpak,
AppImage and virgl details, and verify the result with
`podman exec webtop-run webtop-gpu-report`.

After starting, navigate to `http://localhost:3000` in your web browser to access the interactive Fedora KDE desktop! All your custom desktop preferences, configurations, and files inside `/home/webtop` will be persisted!

#### 2. Running as a Systemd Service via Quadlet
To manage the Webtop container automatically via systemd, copy the provided [webtop.container](webtop.container) file to your systemd Quadlet directory:

* **System-wide**: `/etc/containers/systemd/`
* **Rootless/User**: `~/.config/containers/systemd/`

Once copied, reload the systemd daemon to automatically generate the transient service and start it:

```bash
# For system-wide services:
sudo systemctl daemon-reload
sudo systemctl start webtop.service
sudo systemctl enable webtop.service

# For rootless/user-level services:
systemctl --user daemon-reload
systemctl --user start webtop.service
systemctl --user enable webtop.service
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

### System-wide just recipes

The base image ships a **system-wide justfile** at `/justfile`
(source: [`rootfs/common/justfile`](rootfs/common/justfile)) plus the `just`
command runner. Because `just` walks up to `/`, these recipes work from **any**
working directory. A closer justfile (`~/justfile`, a project justfile) takes
precedence.

```bash
just          # list the base recipes
just be       # become root in a login shell (run0-backed)
just be core  # become the `core` user
just setup-nix  # enable Nix (dx image only; units ship disabled)
```

Full details, precedence rules, and verification evidence:
[docs/system-justfile.md](docs/system-justfile.md).

### Testing
```bash
# Lint container before deployment
bootc container lint
```

## Services & Integrations

### Enabled Services
- `qemu-guest-agent`: VM integration
- `tailscaled`: VPN mesh networking

### Installed Clients (disabled by default)
- `cloudflare-warp`: WARP client (`warp-cli`, `warp-svc`). Enable with
  `sudo systemctl enable --now warp-svc`, then register with
  `warp-cli registration new`.

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
3. Test changes with `bootc container lint` and `just test-vm`
4. Submit pull request
