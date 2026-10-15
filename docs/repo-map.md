# Repository Filesystem Map: `rootfs/` Layering Semantics

This document details the filesystem overlays organized under the `rootfs/` directory, their layering semantics across variants, and the exact `COPY` instructions across all Containerfiles.

---

## Architecture of `rootfs/`

Filesystem overlays in `rootfs/` are copied into container images during build time to provide configuration files, systemd units, helper binaries, and ostree/bootc sysroot settings.

```
rootfs/
├── btrfs_config/               # Btrfs-specific ostree & kernel arguments
│   └── usr/
│       └── lib/
│           ├── bootc/kargs.d/10-btrfs-compression.toml
│           └── ostree/prepare-root.conf
├── common/                     # Base overlay shared by all AlmaLinux bootc images
│   ├── etc/
│   │   ├── containers/         # Nested podman & storage configs
│   │   ├── nix/                # Nix package manager configuration
│   │   ├── pam.d/              # PAM authentication overrides for sshd
│   │   ├── polkit-1/           # Passwordless systemd execution rules
│   │   ├── profile.d/          # Shell login environment scripts
│   │   ├── ssh/sshd_config.d/  # Hardened SSH & persistent hostkey configs
│   │   ├── sudoers.d/          # Passwordless wheel access
│   │   ├── sysctl.d/           # Kernel virtual memory & forwarding tuning
│   │   ├── systemd/system/     # Service drop-ins (podman, sshd, tailscaled)
│   │   └── tmpfiles.d/         # Ephemeral directory creation rules
│   ├── usr/
│   │   ├── lib/
│   │   │   ├── systemd/system/ # Base systemd services & timers (borgmatic, etc.)
│   │   │   ├── sysusers.d/     # System user & group declarations
│   │   │   └── tmpfiles.d/     # Persistent storage paths for services
│   │   ├── libexec/coreos/     # Operational helper scripts
│   │   └── sbin/               # setup-podman-user provisioning script
│   └── var/lib/systemd/linger/ # Systemd user linger settings (core)
├── hci/                        # Hyperconverged infrastructure overlay
│   └── etc/
│       ├── cockpit/            # Cockpit web console configuration
│       ├── containers/systemd/ # Built-in cockpit-ws quadlet container
│       ├── samba/              # Samba global and ZFS sharing configs
│       └── ssh/sshd_config.d/  # Cockpit SSH port settings
├── non_btrfs/                  # Standard ostree sysroot configuration (XFS/ext4)
│   └── usr/lib/ostree/prepare-root.conf
├── webtop/                     # Containerized desktop environment overlay
│   ├── etc/
│   │   ├── nginx/conf.d/       # WebRTC reverse proxy configuration
│   │   └── systemd/system/     # webtop.service systemd unit
│   └── usr/local/bin/          # KWin Wayland startup and Selkies patch scripts
└── workstation/                # Bazzite desktop workstation overlay
    ├── etc/systemd/            # ZRAM generator memory compression configuration
    ├── usr/lib/ostree/         # Workstation-specific prepare-root.conf
    └── usr/share/polkit-1/     # Desktop polkit rules (Bitwarden)
```

---

## Overlay Layering Semantics

### 1. `rootfs/common/` (Shared Base Overlay)
- **Target**: Shared across all AlmaLinux-derived images (base, dx, dockerhost, hci, k3s) and imported by `webtop`.
- **Purpose**: Establishes standard administrative policies:
  - SSH configuration: enforces Ed25519 authentication, disables root password logins, sets up persistent host keys (`/etc/ssh/sshd_config.d/90-persistent-hostkeys.conf`).
  - Container engine defaults: configures nested container execution (`containers.conf.d/20-nested.conf`) and storage (`storage.conf.d/20-host-containers.conf`).
  - Core services: automates bootc auto-updates (`bootc-fetch-apply-updates.timer`), overlay synchronizations (`etc-overlay-sync.service`), and user provisioning (`/usr/sbin/setup-podman-user`).
  - **Developer Assets (`dx`)**: All developer tooling configurations and assets previously located in `rootfs/dx/` reside directly in `rootfs/common/`.

### 2. Filesystem Conditionals: `rootfs/btrfs_config/` vs `rootfs/non_btrfs/`
The bootc ostree sysroot preparation requires filesystem-aware mount and composefs configurations:
- **`rootfs/btrfs_config/`**:
  - Used when the target root filesystem is Btrfs.
  - Deploys `10-btrfs-compression.toml` setting kernel arguments `rootflags=compress=zstd:2`.
  - Configures `prepare-root.conf` with `[composefs] enabled = verity`, `[sysroot] readonly = true`, `[root] transient = true`, `[etc] transient = false`.
  - Active in [workstation.Containerfile](workstation.Containerfile) and ISO installations.
- **`rootfs/non_btrfs/`**:
  - Used when the target root filesystem is XFS or ext4.
  - Configures `prepare-root.conf` with `[composefs] enabled = true`, `[sysroot] readonly = false`, `[root] transient = true`, `[etc] transient = false`.
  - Active in the standard AlmaLinux [Containerfile](Containerfile).

### 3. `rootfs/hci/` (Hyperconverged Infrastructure Overlay)
- **Target**: [hci.Containerfile](hci.Containerfile).
- **Purpose**: Provides Cockpit web administration integration, Cockpit Web Service quadlet container (`cockpit-ws.container.builtin`), and Samba daemon sharing configurations (`smb.conf`, `smb.conf.d/10-global.conf`, `smb.conf.d/20-zfs-global.conf`).

### 4. `rootfs/webtop/` (Webtop Container Overlay)
- **Target**: [webtop.Containerfile](webtop.Containerfile).
- **Purpose**: Configures headless KDE Wayland desktop streaming inside a rootless container:
  - `etc/nginx/conf.d/webtop.conf`: Reverse proxy serving the Selkies web interface over HTTP port 3000.
  - `etc/systemd/system/webtop.service`: Systemd service orchestrating the desktop startup sequence.
  - Helper scripts: `start-webtop.sh`, `kwin-xwayland.py`, and `patch-selkies.py`.

### 5. `rootfs/workstation/` (Bazzite Workstation Overlay)
- **Target**: [workstation.Containerfile](workstation.Containerfile) and [laptop.Containerfile](laptop.Containerfile).
- **Purpose**: Configures desktop memory management (`zram-generator.conf` enabling ZRAM swap) and desktop application security policies (`com.bitwarden.Bitwarden.policy`).

---

## Containerfile `COPY` Mapping Reference

The table below documents which Containerfile copies which `rootfs` subdirectory:

| Containerfile | Base Image (FROM) | `rootfs` Path Copied | Destination | Notes |
| :--- | :--- | :--- | :--- | :--- |
| [Containerfile](Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10` | `rootfs/non_btrfs/`<br>`rootfs/common/` | `/`<br>`/` | Line 149 (`rootfs/btrfs_config/`) is commented out; non-btrfs is active. |
| [dx.Containerfile](dx.Containerfile) | `ghcr.io/braccae/alma:latest` | Inherited from base | N/A | Inherits `rootfs/common/` and `rootfs/non_btrfs/`. Note: dx assets live in `rootfs/common/`. |
| [dockerhost.Containerfile](dockerhost.Containerfile) | `ghcr.io/braccae/alma:latest` | Inherited from base | N/A | Inherits `rootfs/common/` and `rootfs/non_btrfs/` via `base`. |
| [hci.Containerfile](hci.Containerfile) | `ghcr.io/braccae/alma:latest` | `rootfs/hci/` | `/` | Inherits `common` from base; adds HCI-specific Cockpit and Samba files. |
| [installer.Containerfile](installer.Containerfile) | `ghcr.io/braccae/coreos:workstation` | None | N/A | Inherits from `$installer_base`. |
| [k3s.Containerfile](k3s.Containerfile) | `ghcr.io/braccae/alma:latest` | Inherited from base | N/A | Inherits `common` from base; installs k3s binary and systemd service directly. |
| [kmods.Containerfile](kmods.Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10` | None | N/A | Builds ZFS kernel modules into a scratch image. |
| [kmods-bundle.Containerfile](kmods-bundle.Containerfile) | `scratch` | None | N/A | Bundles pre-built multi-arch RPM trees from `zfs/`. |
| `test.Containerfile` | Configurable | None (Scratch) | N/A | Local developer scratch containerfile. |
| [laptop.Containerfile](laptop.Containerfile) | `ghcr.io/ublue-os/bazzite-dx-gnome` | `rootfs/workstation/` | `/` | Copies workstation overlay on top of Bazzite DX GNOME. |
| [webtop.Containerfile](webtop.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-43` | `rootfs/common/`<br>`rootfs/webtop/` | `/`<br>`/` | Reuses core system utilities from `common/` alongside desktop streaming files from `webtop/`. |
| [workstation.Containerfile](workstation.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-44` | `rootfs/btrfs_config/`<br>`rootfs/workstation/` | `/`<br>`/` | **FROZEN PRODUCTION IMAGE**. Lines 63-64 (`non_btrfs/`, `common/`) are commented out. |
