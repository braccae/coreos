# Image Variants Reference

This repository maintains 12 Containerfiles across two primary OS families: **AlmaLinux** (bootc enterprise server and infrastructure variants) and **Bazzite** (gaming, desktop, and workstation variants).

---

## Complete Variant Matrix

| Containerfile | Base Image (`FROM`) | Purpose | Distribution Family | CI Workflow | Status / Constraints |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [Containerfile](file:///home/pants/Projects/container_projects/coreos/Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10` | Base bootc OS; server baseline with Cockpit, Tailscale, ZFS support | AlmaLinux | `.github/workflows/container.yml` | Base image. Published to `ghcr.io/braccae/alma:latest`. |
| [dockerhost.Containerfile](file:///home/pants/Projects/container_projects/coreos/dockerhost.Containerfile) | `ghcr.io/braccae/alma:latest` | Dedicated Docker CE runtime node with Cockpit Docker UI | AlmaLinux | `.github/workflows/container-dockerhost.yml` | Multi-stage build compiles `cockpit-docker` RPM from git. |
| [dx.Containerfile](file:///home/pants/Projects/container_projects/coreos/dx.Containerfile) | `ghcr.io/braccae/alma:latest` | Developer workstation variant with rootless Podman, Nix, and overlay sync | AlmaLinux | **None** | No automated CI workflow. Built manually or locally. Assets live in `rootfs/common/`. |
| [hci.Containerfile](file:///home/pants/Projects/container_projects/coreos/hci.Containerfile) | `ghcr.io/braccae/alma:latest` | Hyperconverged infrastructure host (QEMU/KVM, Cockpit Machines, Samba sharing) | AlmaLinux | `.github/workflows/container-hci.yml` | Includes full libvirt virtualization stack and 45Drives cockpit plugins. |
| [installer.Containerfile](file:///home/pants/Projects/container_projects/coreos/installer.Containerfile) | `ghcr.io/braccae/coreos:workstation`<br>*(configurable via `ARG installer_base`)* | Bootable Anaconda installer build environment for ISO production | AlmaLinux | `.github/workflows/container-installer.yml` | Installs anaconda runtime and lorax templates. |
| [k3s.Containerfile](file:///home/pants/Projects/container_projects/coreos/k3s.Containerfile) | `ghcr.io/braccae/alma:latest` | Lightweight single-node or worker Kubernetes (k3s) appliance | AlmaLinux | `.github/workflows/container-k3s.yml` | Installs k3s SELinux policy and upstream k3s binary. |
| [kmods.Containerfile](file:///home/pants/Projects/container_projects/coreos/kmods.Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10`<br>*(configurable via `ARG BASE_IMAGE`)* | Compiles OpenZFS kernel modules and signs binaries using Secure Boot MOK | AlmaLinux | `.github/workflows/container-kmods.yml` (build job) | Builds matrix targets (`alma-amd64`, `alma-arm64`, `bazzite-amd64`). |
| [kmods-bundle.Containerfile](file:///home/pants/Projects/container_projects/coreos/kmods-bundle.Containerfile) | `scratch` | Aggregates compiled multi-arch ZFS RPM trees into a unified distribution container | AlmaLinux | `.github/workflows/container-kmods.yml` (bundle job) | Emits `ghcr.io/braccae/kmods:latest` containing `/zfs/`. |
| `test.Containerfile` | Configurable | Ephemeral test container definition for local validation | AlmaLinux | **None** | Explicitly git-ignored. Used for scratch builds. |
| [laptop.Containerfile](file:///home/pants/Projects/container_projects/coreos/laptop.Containerfile) | `ghcr.io/ublue-os/bazzite-dx-gnome` | Mobile developer workstation with GNOME desktop environment | Bazzite | `.github/workflows/container-laptop.yml` | Installs developer tooling, Ansible, Java, and Bazzite overlays. |
| [webtop.Containerfile](file:///home/pants/Projects/container_projects/coreos/webtop.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-43` | Containerized remote KDE Wayland desktop accessible over HTTP via Selkies | Bazzite | `.github/workflows/container-webtop.yml` | Experimental rootless desktop streaming container. |
| [workstation.Containerfile](file:///home/pants/Projects/container_projects/coreos/workstation.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-44` | Primary desktop workstation image with KDE, ZFS, and virtualization tools | Bazzite | `.github/workflows/container-workstation.yml` | **FROZEN PRODUCTION IMAGE**. Must not be modified. |

---

## Detailed Variant Specifications

### AlmaLinux Family (9 Containerfiles)

1. **[Containerfile](file:///home/pants/Projects/container_projects/coreos/Containerfile) (Base)**
   - **Build Source**: `FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base` (Line 2).
   - **Published Tag**: `ghcr.io/braccae/alma:latest`.
   - **Role**: Foundational bootc base for all Alma derivatives. Integrates Tailscale, Cockpit management plugins, EPEL/RPM Fusion repositories, ZFS module ingestion, and rootless Podman user provisioning.
   - **Overlay**: Copies `rootfs/non_btrfs/` and `rootfs/common/`.

2. **[dockerhost.Containerfile](file:///home/pants/Projects/container_projects/coreos/dockerhost.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest as base`.
   - **Role**: Optimized Docker runtime environment. Installs Docker CE, containerd, and builds the Cockpit Docker management module from source.

3. **[dx.Containerfile](file:///home/pants/Projects/container_projects/coreos/dx.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest AS base`.
   - **Role**: Lightweight developer image equipped with Podman, Docker CLI compatibility, Compose, Nix, and transient `/etc` overlay synchronization.
   - **Overlay**: Assets reside in `rootfs/common/` (dx-specific overlay directory was merged into common).
   - **CI Note**: No automated CI workflow exists; built locally or ad-hoc.

4. **[hci.Containerfile](file:///home/pants/Projects/container_projects/coreos/hci.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest`.
   - **Role**: Hyperconverged infrastructure host. Bundles QEMU/KVM hardware virtualization, libvirt daemon drivers, Cockpit Machines web UI, Samba file sharing, and 45Drives identities/sharing extensions.
   - **Overlay**: Copies `rootfs/hci/`.

5. **[installer.Containerfile](file:///home/pants/Projects/container_projects/coreos/installer.Containerfile)**
   - **Build Source**: `ARG installer_base=ghcr.io/braccae/coreos:workstation`, `FROM $installer_base`.
   - **Role**: Utility environment providing Anaconda installer binaries, dracut network tooling, and Lorax templates used to produce bootable installation media.

6. **[k3s.Containerfile](file:///home/pants/Projects/container_projects/coreos/k3s.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest`.
   - **Role**: Single-binary Kubernetes host. Pre-configures k3s SELinux policy RPM and installs the official k3s binary into `/usr/bin`.

7. **[kmods.Containerfile](file:///home/pants/Projects/container_projects/coreos/kmods.Containerfile)**
   - **Build Source**: `ARG BASE_IMAGE=quay.io/almalinuxorg/almalinux-bootc:10`, `FROM ${BASE_IMAGE} AS zfs-builder`.
   - **Role**: Kernel module compiler. Clones OpenZFS source, compiles kmods against target kernel headers, signs binaries with Secure Boot MOK keys, writes `kernel-version.txt`, and emits a minimal scratch container with RPM artifacts.

8. **[kmods-bundle.Containerfile](file:///home/pants/Projects/container_projects/coreos/kmods-bundle.Containerfile)**
   - **Build Source**: `FROM scratch`.
   - **Role**: Aggregator image. Copies multi-architecture directory trees (`zfs/alma/amd64/`, `zfs/alma/arm64/`, `zfs/bazzite/amd64/`) into a single container tag (`ghcr.io/braccae/kmods:latest`) consumed by downstream builds.

9. **`test.Containerfile`**
   - **Build Source**: User-configurable.
   - **Role**: Local developer scratchpad. Git-ignored in `.gitignore` to prevent accidental commits of local experimentation.

---

### Bazzite Family (3 Containerfiles)

10. **[laptop.Containerfile](file:///home/pants/Projects/container_projects/coreos/laptop.Containerfile)**
    - **Build Source**: `FROM ghcr.io/ublue-os/bazzite-dx-gnome`.
    - **Role**: Developer laptop image. Based on Universal Blue Bazzite with GNOME, adding development environments (VS Code, Java 21, Ansible) via [build/justfile](file:///home/pants/Projects/container_projects/coreos/build/justfile).
    - **Overlay**: Copies `rootfs/workstation/`.

11. **[webtop.Containerfile](file:///home/pants/Projects/container_projects/coreos/webtop.Containerfile)**
    - **Build Source**: `FROM ghcr.io/ublue-os/bazzite:stable-43 as base`.
    - **Role**: Browser-accessible KDE Wayland desktop streaming environment running inside an unprivileged rootless container. Uses Selkies/Pixelflux WebRTC streaming on port 3000.
    - **Overlay**: Copies `rootfs/common/` and `rootfs/webtop/`.
    - **CI Note**: Automated CI workflow `.github/workflows/container-webtop.yml`.

12. **[workstation.Containerfile](file:///home/pants/Projects/container_projects/coreos/workstation.Containerfile)**
    - **Build Source**: `FROM ghcr.io/ublue-os/bazzite:stable-44 AS base`.
    - **Role**: Primary desktop workstation operating system with KDE Plasma, ZFS filesystem support via kmods, virtualization tools, and development tooling.
    - **Overlay**: Copies `rootfs/btrfs_config/` and `rootfs/workstation/`.
    - **CRITICAL HARD RULE**: **DO NOT MODIFY THIS FILE**. A live production machine depends directly on this specification. Any modification risks destabilizing production hardware.

---

## CI Workflow Cross-Reference

| Workflow File | Target Containerfile | Trigger Branches / Conditions | Downstream Triggers |
| :--- | :--- | :--- | :--- |
| `.github/workflows/container.yml` | [Containerfile](file:///home/pants/Projects/container_projects/coreos/Containerfile) | Push to `main`, `Containerfile`, `rootfs/**` | Triggers downstream image builds |
| `.github/workflows/container-dockerhost.yml` | [dockerhost.Containerfile](file:///home/pants/Projects/container_projects/coreos/dockerhost.Containerfile) | Push to `main`, `dockerhost.Containerfile` | None |
| `.github/workflows/container-hci.yml` | [hci.Containerfile](file:///home/pants/Projects/container_projects/coreos/hci.Containerfile) | Push to `main`, `hci.Containerfile`, `rootfs/hci/**` | None |
| `.github/workflows/container-installer.yml` | [installer.Containerfile](file:///home/pants/Projects/container_projects/coreos/installer.Containerfile) | Push to `main`, `installer.Containerfile` | None |
| `.github/workflows/container-k3s.yml` | [k3s.Containerfile](file:///home/pants/Projects/container_projects/coreos/k3s.Containerfile) | Push to `main`, `k3s.Containerfile` | None |
| `.github/workflows/container-kmods.yml` | [kmods.Containerfile](file:///home/pants/Projects/container_projects/coreos/kmods.Containerfile)<br>[kmods-bundle.Containerfile](file:///home/pants/Projects/container_projects/coreos/kmods-bundle.Containerfile) | Push to `main`, `kmods*.Containerfile`, `build-zfs.sh` | Dispatches `container.yml` and `container-workstation.yml` |
| `.github/workflows/container-laptop.yml` | [laptop.Containerfile](file:///home/pants/Projects/container_projects/coreos/laptop.Containerfile) | Push to `main`, `laptop.Containerfile` | None |
| `.github/workflows/container-workstation.yml` | [workstation.Containerfile](file:///home/pants/Projects/container_projects/coreos/workstation.Containerfile) | Push to `main`, `workstation.Containerfile`, `rootfs/workstation/**` | None |
| *(None)* | [dx.Containerfile](file:///home/pants/Projects/container_projects/coreos/dx.Containerfile) | N/A (Manual / Local builds only) | None |
| `.github/workflows/container-webtop.yml` | [webtop.Containerfile](file:///home/pants/Projects/container_projects/coreos/webtop.Containerfile) | Push to `main`, `webtop.Containerfile`, `rootfs/webtop/**` | None |
