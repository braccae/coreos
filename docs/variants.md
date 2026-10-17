# Image Variants Reference

This repository maintains 13 Containerfiles across two primary OS families: **AlmaLinux** (bootc enterprise server and infrastructure variants) and **Bazzite** (gaming, desktop, and workstation variants).

---

## Complete Variant Matrix

| Containerfile | Base Image (`FROM`) | Purpose | Distribution Family | CI Workflow | Status / Constraints |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [Containerfile](Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10` | Base bootc OS; server baseline with Cockpit, Tailscale, ZFS support | AlmaLinux | `.github/workflows/container.yml` | Base image. Published to `ghcr.io/braccae/alma:latest`. |
| [dockerhost.Containerfile](dockerhost.Containerfile) | `ghcr.io/braccae/alma:latest` | Dedicated Docker CE runtime node with Cockpit Docker UI | AlmaLinux | `.github/workflows/container-dockerhost.yml` | Multi-stage build compiles `cockpit-docker` RPM from git. |
| [dx.Containerfile](dx.Containerfile) | `ghcr.io/braccae/alma:latest` | Developer workstation variant with rootless Podman, Nix, and overlay sync | AlmaLinux | `.github/workflows/container-dx.yml` | Published as `ghcr.io/braccae/alma:dx`. Assets live in `rootfs/common/`. |
| [hci.Containerfile](hci.Containerfile) | `ghcr.io/braccae/alma:latest` | Hyperconverged infrastructure host (QEMU/KVM, Cockpit Machines, Samba sharing) | AlmaLinux | `.github/workflows/container-hci.yml` | Includes full libvirt virtualization stack and 45Drives cockpit plugins. |
| [installer.Containerfile](installer.Containerfile) | `ghcr.io/braccae/coreos:workstation`<br>*(configurable via `ARG installer_base`)* | Bootable Anaconda installer build environment for ISO production | AlmaLinux | `.github/workflows/container-installer.yml` | Installs anaconda runtime and lorax templates. |
| [k3s.Containerfile](k3s.Containerfile) | `ghcr.io/braccae/alma:latest` | Lightweight single-node or worker Kubernetes (k3s) appliance | AlmaLinux | `.github/workflows/container-k3s.yml` | Installs k3s SELinux policy and upstream k3s binary. |
| [kmods.Containerfile](kmods.Containerfile) | `quay.io/almalinuxorg/almalinux-bootc:10`<br>*(configurable via `ARG BASE_IMAGE`)* | Compiles OpenZFS kernel modules and signs binaries using Secure Boot MOK | AlmaLinux | `.github/workflows/container-kmods.yml` (build job) | Builds matrix targets (`alma-amd64`, `alma-arm64`, `bazzite-amd64`). |
| [kmods-bundle.Containerfile](kmods-bundle.Containerfile) | `scratch` | Aggregates compiled multi-arch ZFS RPM trees into a unified distribution container | AlmaLinux | `.github/workflows/container-kmods.yml` (bundle job) | Emits `ghcr.io/braccae/kmods:latest` containing `/zfs/`. |
| `test.Containerfile` | Configurable | Ephemeral test container definition for local validation | AlmaLinux | **None** | Explicitly git-ignored. Used for scratch builds. |
| [laptop.Containerfile](laptop.Containerfile) | `ghcr.io/ublue-os/bazzite-dx-gnome` | Mobile developer workstation with GNOME desktop environment | Bazzite | `.github/workflows/container-laptop.yml` | Installs developer tooling, Ansible, Java, and Bazzite overlays. |
| [webtop.Containerfile](webtop.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-43` | Containerized remote KDE Wayland desktop accessible over HTTP via Selkies | Bazzite | `.github/workflows/container-webtop.yml` | Experimental rootless desktop streaming container. |
| [workstation.Containerfile](workstation.Containerfile) | `ghcr.io/ublue-os/bazzite:stable-44` | Primary desktop workstation image with KDE, ZFS, and virtualization tools | Bazzite | `.github/workflows/container-workstation.yml` | **FROZEN PRODUCTION IMAGE**. Must not be modified. |
| [workstation-alma.Containerfile](workstation-alma.Containerfile) | `ghcr.io/braccae/alma:latest` | Local KDE Plasma 6 desktop workstation (SDDM, virtualization, dev tooling) | AlmaLinux | `.github/workflows/container-workstation-alma.yml` | AlmaLinux equivalent of the Bazzite workstation image. |

---

## Detailed Variant Specifications

### AlmaLinux Family (10 Containerfiles)

1. **[Containerfile](Containerfile) (Base)**
   - **Build Source**: `FROM quay.io/almalinuxorg/almalinux-bootc:10 AS base` (Line 2).
   - **Published Tag**: `ghcr.io/braccae/alma:latest`.
   - **Role**: Foundational bootc base for all Alma derivatives. Integrates Tailscale, Cockpit management plugins, EPEL/RPM Fusion repositories, ZFS module ingestion, and rootless Podman user provisioning.
   - **Overlay**: Copies `rootfs/non_btrfs/` and `rootfs/common/`.

2. **[dockerhost.Containerfile](dockerhost.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest as base`.
   - **Role**: Optimized Docker runtime environment. Installs Docker CE, containerd, and builds the Cockpit Docker management module from source.

3. **[dx.Containerfile](dx.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest AS base`.
   - **Role**: Lightweight developer image equipped with Podman, Docker CLI compatibility, Compose, Nix, and transient `/etc` overlay synchronization.
   - **Overlay**: Assets reside in `rootfs/common/` (dx-specific overlay directory was merged into common).
   - **CI Note**: Built and published by `.github/workflows/container-dx.yml` as `ghcr.io/braccae/alma:dx`.

4. **[hci.Containerfile](hci.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest`.
   - **Role**: Hyperconverged infrastructure host. Bundles QEMU/KVM hardware virtualization, libvirt daemon drivers, Cockpit Machines web UI, Samba file sharing, and 45Drives identities/sharing extensions.
   - **Overlay**: Copies `rootfs/hci/`.

5. **[installer.Containerfile](installer.Containerfile)**
   - **Build Source**: `ARG installer_base=ghcr.io/braccae/coreos:workstation`, `FROM $installer_base`.
   - **Role**: Utility environment providing Anaconda installer binaries, dracut network tooling, and Lorax templates used to produce bootable installation media.

6. **[k3s.Containerfile](k3s.Containerfile)**
   - **Build Source**: `FROM ghcr.io/braccae/alma:latest`.
   - **Role**: Single-binary Kubernetes host. Pre-configures k3s SELinux policy RPM and installs the official k3s binary into `/usr/bin`.

7. **[kmods.Containerfile](kmods.Containerfile)**
   - **Build Source**: `ARG BASE_IMAGE=quay.io/almalinuxorg/almalinux-bootc:10`, `FROM ${BASE_IMAGE} AS kmods-builder`.
   - **Role**: Kernel module compiler. Clones OpenZFS source, compiles the ZFS kmods against target kernel headers, signs the binaries with the Secure Boot MOK key (when the `LOCALMOK` secret is provided), writes `kernel-version.txt`, and emits a minimal scratch container with RPM artifacts.

8. **[kmods-bundle.Containerfile](kmods-bundle.Containerfile)**
   - **Build Source**: `FROM scratch`.
   - **Role**: Aggregator image. Copies multi-architecture directory trees (`zfs/alma/amd64/`, `zfs/alma/arm64/`, `zfs/bazzite/amd64/`) into a single container tag (`ghcr.io/braccae/kmods:latest`) consumed by downstream builds.

9. **`test.Containerfile`**
   - **Build Source**: User-configurable.
   - **Role**: Local developer scratchpad. Git-ignored in `.gitignore` to prevent accidental commits of local experimentation.

10. **[workstation-alma.Containerfile](workstation-alma.Containerfile)**
    - **Build Source**: `FROM ghcr.io/braccae/alma:latest`.
    - **Role**: Local KDE Plasma 6 desktop workstation. Installs the KDE Plasma stack from EPEL, SDDM display manager (Wayland), virtualization tooling (virt-manager, QEMU/KVM), Java 21, and dev tooling (VS Code, GitHub CLI, pnpm).
    - **Overlay**: Copies `rootfs/workstation-alma/`.
    - **CI Note**: Automated CI workflow `.github/workflows/container-workstation-alma.yml`.

---

### Bazzite Family (3 Containerfiles)

11. **[laptop.Containerfile](laptop.Containerfile)**
    - **Build Source**: `FROM ghcr.io/ublue-os/bazzite-dx-gnome`.
    - **Role**: Developer laptop image. Based on Universal Blue Bazzite with GNOME, adding development environments (VS Code, Java 21, Ansible) via [build/justfile](build/justfile).
    - **Overlay**: Copies `rootfs/workstation/`.

12. **[webtop.Containerfile](webtop.Containerfile)**
    - **Build Source**: `FROM ghcr.io/ublue-os/bazzite:stable-43 as base`.
    - **Role**: Browser-accessible KDE Wayland desktop streaming environment running inside an unprivileged rootless container. Uses Selkies/Pixelflux WebRTC streaming on port 3000.
    - **Overlay**: Copies `rootfs/common/` and `rootfs/webtop/`.
    - **CI Note**: Automated CI workflow `.github/workflows/container-webtop.yml`.

13. **[workstation.Containerfile](workstation.Containerfile)**
    - **Build Source**: `FROM ghcr.io/ublue-os/bazzite:stable-44 AS base`.
    - **Role**: Primary desktop workstation operating system with KDE Plasma, ZFS filesystem support via kmods, virtualization tools, and development tooling.
    - **Overlay**: Copies `rootfs/btrfs_config/` and `rootfs/workstation/`.
    - **CRITICAL HARD RULE**: **DO NOT MODIFY THIS FILE**. A live production machine depends directly on this specification. Any modification risks destabilizing production hardware.

---

## CI Workflow Cross-Reference

| Workflow File | Target Containerfile | Trigger Branches / Conditions | Downstream Triggers |
| :--- | :--- | :--- | :--- |
| `.github/workflows/container.yml` | [Containerfile](Containerfile) | Push to `main`, `Containerfile`, `rootfs/**` | Triggers downstream image builds |
| `.github/workflows/container-dockerhost.yml` | [dockerhost.Containerfile](dockerhost.Containerfile) | Push to `main`, `dockerhost.Containerfile` | None |
| `.github/workflows/container-hci.yml` | [hci.Containerfile](hci.Containerfile) | Push to `main`, `hci.Containerfile`, `rootfs/hci/**` | None |
| `.github/workflows/container-installer.yml` | [installer.Containerfile](installer.Containerfile) | Push to `main`, `installer.Containerfile` | None |
| `.github/workflows/container-k3s.yml` | [k3s.Containerfile](k3s.Containerfile) | Push to `main`, `k3s.Containerfile` | None |
| `.github/workflows/container-kmods.yml` | [kmods.Containerfile](kmods.Containerfile)<br>[kmods-bundle.Containerfile](kmods-bundle.Containerfile) | Push to `main`, `kmods*.Containerfile`, `build-zfs.sh` | Dispatches `container.yml` and `container-workstation.yml` |
| `.github/workflows/container-laptop.yml` | [laptop.Containerfile](laptop.Containerfile) | Push to `main`, `laptop.Containerfile` | None |
| `.github/workflows/container-workstation.yml` | [workstation.Containerfile](workstation.Containerfile) | Push to `main`, `workstation.Containerfile`, `rootfs/workstation/**` | None |
| `.github/workflows/container-workstation-alma.yml` | [workstation-alma.Containerfile](workstation-alma.Containerfile) | Push to `main`, `workstation-alma.Containerfile`, `rootfs/workstation-alma/**` | None |
| `.github/workflows/container-dx.yml` | [dx.Containerfile](dx.Containerfile) | Push to `main`, `dx.Containerfile`, `rootfs/common/**` | None |
| `.github/workflows/container-webtop.yml` | [webtop.Containerfile](webtop.Containerfile) | Push to `main`, `webtop.Containerfile`, `rootfs/webtop/**` | None |
