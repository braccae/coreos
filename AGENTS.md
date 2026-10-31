# AGENTS.md - CoreOS Bootc Repository Guide

Agent entry point for `/home/pants/Projects/container_projects/coreos`.
Follow these rules and references when working in this repository.

---

## What This Repo Is

This repository maintains bootable container (`bootc`) operating system images, build automation, filesystem overlays, and disk image generation recipes.

- **Primary Stack**: AlmaLinux 10 bootc (`quay.io/almalinuxorg/almalinux-bootc:10`), publishing to `ghcr.io/braccae/alma:latest`.
- **Variants**: Specialized Alma-derived servers (HCI, Docker host, k3s, dev workstation, kmods, installer) and Fedora/Bazzite-derived workstations (`laptop`, `webtop`, `workstation`).
- **Disk Artifacts**: Bootable `qcow2` virtual machine images and `bootc-installer` ISOs generated via `quay.io/centos-bootc/bootc-image-builder:latest`.

---

## HARD RULES

1. **Base Build FROM**: The base image in [Containerfile](Containerfile#L2) builds `FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base`. The tag `ghcr.io/braccae/alma:latest` is the **PUBLISHED output** of this build, NOT the build input. Never change line 2 of [Containerfile](Containerfile#L2) to pull from `ghcr.io/braccae/alma:latest`.
2. **Workstation Image Frozen**: [workstation.Containerfile](workstation.Containerfile) **MUST NOT BE MODIFIED**. A physical production machine depends on this exact image specification.
3. **No Contradictions of Verified Facts**: Do not alter verified architectural facts regarding variants, build stages, or base distributions.
4. **Local Reproduction Resource Limits**: Local test VM execution defaults to **2048 MB RAM** and **2 vCPUs** (`just test-vm` accepts overrides, e.g. `just test-vm latest 4096 4`). Keep local VM usage modest so the host stays responsive. Local testing uses rootless Podman alongside rootful KVM (`virsh`/`virt-install`).
5. **Git Worktree Isolation**: Never develop directly on `main` or in the primary checkout. All feature and task development happens in dedicated worktrees under `.worktrees/<branch-name>`.
6. **Caveman Payload-Verbatim Rule**: When communications require terseness or brevity, all functional payloads (code snippets, configuration blocks, diffs, terminal commands) must be provided **verbatim** without ellipses, trimming, or omissions.

---

## Repo Map

```
.
├── Containerfile               # Base AlmaLinux 10 bootc image definition
├── *.Containerfile             # Variant image definitions (11 additional files)
├── AGENTS.md                   # Agent entry point (this file)
├── build/                      # Build configurations and helpers
│   ├── config-img.toml         # bootc-image-builder qcow2 configuration
│   ├── config-iso.toml         # bootc-image-builder anaconda ISO configuration
│   ├── justfile                # Helper recipes invoked during container builds
│   ├── scripts/                # ZFS build, SELinux validation, and installer scripts
│   └── selinux/                # Custom SELinux policy modules
├── dev-tools/                  # Disk image build helpers
│   └── scripts/install/        # podman-build-disk-image.sh, write-disk-image-to-disk.sh
├── docs/                       # Architectural documentation
│   ├── backup.md               # Current and target backup architecture
│   ├── build-system.md         # Multi-staging, bootc lint, kmods, and just recipes
│   ├── conventions.md          # Branching, worktree, commit, and PR standards
│   ├── repo-map.md             # rootfs/ layering semantics and COPY mapping
│   ├── testing.md              # 4 run-mode contracts and local reproduction limits
│   └── variants.md             # Complete matrix of all 12 Containerfiles
├── justfile                    # Root workspace automation recipes
├── keys/                       # Secure Boot MOK keys for kernel module signing
├── quadlets/                   # Example systemd quadlet container definitions
├── repos/                      # RPM repository configuration files
└── rootfs/                     # Layered filesystem overlays
    ├── btrfs_config/           # Btrfs mount kargs and composefs config
    ├── common/                 # Base filesystem overlay for all Alma images
    ├── dx/                     # dx-only overlay: Nix units, config and tmpfiles
    ├── hci/                    # Cockpit, QEMU, Samba configuration for HCI
    ├── non_btrfs/              # Standard composefs config for non-btrfs root
    ├── webtop/                 # Nginx, Selkies, and systemd units for Webtop
    └── workstation/            # ZRAM and polkit configs for Workstation/Laptop
```

Detailed overlay semantics and COPY mappings are documented in [docs/repo-map.md](docs/repo-map.md).

---

## Build Commands

Common recipes are orchestrated via `just` (see [justfile](justfile)):

```bash
# Build base AlmaLinux container image locally
podman build -f Containerfile -t localhost/alma:latest .

# Build specific variant container image locally
podman build -f <variant>.Containerfile -t localhost/<variant>:latest .

# Build qcow2 disk image via bootc-image-builder (rootful podman)
just build-disk-image alma latest

# Build bootc installer ISO (rootful podman)
just build-iso alma latest

# Write qcow2 disk image to a raw block device (DANGER: destroys target disk)
just write-disk-image /dev/sdX alma latest

# Regenerate Secure Boot MOK key pair
just regen-mok

# Validate local VM test dependencies
just check-vm-deps

# Build and run ephemeral 2048MB test VM
just test-vm latest 2048 2
```

Full build pipeline and multi-staging patterns are documented in [docs/build-system.md](docs/build-system.md).

---

## Variant Table

Summary of all 12 Containerfiles in this repository:

| Containerfile | Base (FROM) | Purpose | Family | CI Workflow |
| :--- | :--- | :--- | :--- | :--- |
| [Containerfile](Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10` | Core bootc server image | Alma | `container.yml` |
| [dockerhost.Containerfile](dockerhost.Containerfile) | `ghcr.io/braccae/alma:latest` | Docker engine host with Cockpit UI | Alma | `container-dockerhost.yml` |
| [dx.Containerfile](dx.Containerfile) | `ghcr.io/braccae/alma:latest` | Developer workstation (dx-only Nix, Podman) | Alma | `container-dx.yml` |
| [hci.Containerfile](hci.Containerfile) | `ghcr.io/braccae/alma:latest` | Hyperconverged virt host (KVM, Cockpit) | Alma | `container-hci.yml` |
| [installer.Containerfile](installer.Containerfile) | `ghcr.io/braccae/coreos:workstation` | Anaconda installer builder environment | Alma | `container-installer.yml` |
| [k3s.Containerfile](k3s.Containerfile) | `ghcr.io/braccae/alma:latest` | Lightweight Kubernetes node | Alma | `container-k3s.yml` |
| [kmods.Containerfile](kmods.Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10` | Compiles & signs ZFS kernel modules | Alma | `container-kmods.yml` |
| [kmods-bundle.Containerfile](kmods-bundle.Containerfile) | `scratch` | Multi-arch bundle of compiled ZFS RPMs | Alma | `container-kmods.yml` |
| `test.Containerfile` | Configurable | Ephemeral local scratch testing (git-ignored) | Alma | None |
| [laptop.Containerfile](laptop.Containerfile) | `ghcr.io/ublue-os/bazzite-dx-gnome` | Bazzite GNOME mobile workstation | Bazzite | `container-laptop.yml` |
| [webtop.Containerfile](webtop.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-43` | Remote KDE Wayland desktop in container | Bazzite | `container-webtop.yml` |
| [workstation.Containerfile](workstation.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-44` | Production KDE desktop (**DO NOT MODIFY**) | Bazzite | `container-workstation.yml` |

Full variant details and relationships are documented in [docs/variants.md](docs/variants.md).

---

## Testing

Every change must satisfy the 4 run-mode contract where applicable:

1. **`bootc-vm`**: Full OS boot in KVM (local) or TCG emulation (CI). Acceptance: clean UEFI boot to `multi-user.target`, user `core` accessible via SSH/serial console.
2. **`rootless-systemd`**: Rootless Podman container run with `--systemd=always` as an unprivileged user. Acceptance: systemd boots as PID 1 without host privilege escalation.
3. **`rootless-app`**: Direct application container without systemd or PID 1 init. Acceptance: fast start, non-root execution, clean exit without zombie processes.
4. **`rootless-multi`**: Multi-process container with systemd running under user namespaces with `fuse-overlayfs`. Acceptance: nested containers and user quadlets operate within allotted subuids.

Local reproduction constraints and test commands are documented in [docs/testing.md](docs/testing.md).

---

## Conventions

- **Branches**: `feature/<category>` or `task/<id>`.
- **Worktrees**: Use `.worktrees/<name>` to isolate development from the repository root.
- **Commits**: Conventional Commit specification (`feat:`, `fix:`, `docs:`, `chore:`).
- **PR Evidence**: Every pull request must include proof of test execution (lint outputs, VM boot verification, or local build logs).

Full contribution and style conventions are documented in [docs/conventions.md](docs/conventions.md).

---

## Documentation Links

- [docs/repo-map.md](docs/repo-map.md) - `rootfs/` overlay structure and COPY mappings.
- [docs/build-system.md](docs/build-system.md) - Containerfile staging, `bootc container lint`, `kmods`, and build tooling.
- [docs/variants.md](docs/variants.md) - Comprehensive variant table and specifications.
- [docs/testing.md](docs/testing.md) - 4 run-mode testing contracts, criteria, and reproduction.
- [docs/conventions.md](docs/conventions.md) - Workflow, branching, worktrees, and commit conventions.
- [docs/backup.md](docs/backup.md) - Current Borgmatic setup and target migration to Restic + Databasus.
