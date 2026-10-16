# Backup Architecture: Current and Target State

This document outlines the backup infrastructure for hosts running images built from this repository. The legacy wrapper units and build stages have been retired in favor of a decoupled backup strategy utilizing Restic and Databasus (`borgbackup` remains installed solely to read and migrate existing Borg repositories).

---

## Architectural Comparison

| Dimension | Legacy State (Retired) | Current State (Restic + Databasus) |
| :--- | :--- | :--- |
| **Primary Engine (Files/Appdata)** | Legacy Borg wrapper (`borgbackup` retained for migration) | **Restic** |
| **Primary Engine (Databases)** | Monolithic internal database dump hooks | **Databasus** |
| **Package Management** | Compiled Python wheel in multi-stage build (retired) | Standalone Go binaries & dedicated quadlet containers |
| **Systemd Units** | Legacy host timer/service units (removed from `rootfs/common/`) | System/user quadlets (`databasus.container`, `databasus.volume`) & restic systemd timers |
| **SELinux Integration** | Custom SELinux policy module (removed) | Standard container/system policies |
| **Repository Backend** | SSH Borg repositories / local drives | S3-compatible object storage, B2, or local storage |
| **Status** | Retired (`borgbackup` CLI kept for repo migration) | Active |

---

## Current State: Central Database Backups (Databasus) & Restic

The active backup architecture decouples stateful database dumps from general filesystem and application data snapshots:

```mermaid
flowchart TD
    Volume["rootfs/common/etc/containers/systemd/databasus.volume<br/>(VolumeName=databasus-data)"]
    Container["rootfs/common/etc/containers/systemd/databasus.container<br/>(docker.io/databasus/databasus:latest on 127.0.0.1:4005)"]
    Service["databasus.service<br/>(Opt-in via systemctl enable --now databasus)"]

    Volume --> Container
    Container --> Service
```

### 1. Build Stage Integration
In [Containerfile](Containerfile):
- The legacy Python wrapper builder stage has been removed.
- System packages retained in the `final` stage include `borgbackup` (for validating and migrating existing Borg archives), `rclone`, and `rsync`.

### 2. System Quadlet Units
Installed in `rootfs/common/etc/containers/systemd/`:
- **`databasus.volume`**:
  - Provisions the persistent `databasus-data` Podman volume (`VolumeName=databasus-data`).
- **`databasus.container`**:
  - Runs `docker.io/databasus/databasus:latest` mounted at `/databasus-data`.
  - Publishes the web UI strictly on `127.0.0.1:4005:4005` because the UI stores database credentials.
  - Shipped opt-in (`WantedBy=default.target`); operators enable it on the central backup host via `systemctl enable --now databasus`.

### 3. SELinux Policy
- Custom backup SELinux modules and `.github/workflows/selinux.yml` have been retired; Databasus runs under standard Podman container SELinux confinement.

---

## Target State: Restic + Databasus Migration

The architecture decouples general filesystem and application data backups from stateful database backups.

### 1. Restic for Files and Appdata
- **Purpose**: Fast, secure, deduplicated backups of host directories (`/etc`, `/var`, `/home`) and application data (`/home/*/appdata`).
- **Advantages over Legacy Wrapper**:
  - Native Go binary with no Python or C-extension runtime dependencies.
  - Native first-class support for cloud object storage (S3, Backblaze B2, MinIO, Azure) without relying on SSH bridges or local FUSE mounts.
  - Significantly faster index traversal and snapshot operations.
- **Implementation**:
  - Standalone binary packaged directly or pulled via container.
  - Scheduled via user-level or system-level systemd timers running rootless where appropriate.

### 2. Databasus for Databases
- **Purpose**: Dedicated, isolated database dump management and snapshotting for relational and document engines (PostgreSQL, MySQL, MariaDB, MongoDB).
- **Advantages over Monolithic Hooks**:
  - Avoids running database client dump hooks inside the monolithic host backup process.
  - Runs as an independent container service (`rootfs/common/etc/containers/systemd/databasus.container`) with native database connection management, compression, verification, and rotation.
  - Consistent point-in-time recovery without locking the entire host filesystem snapshot.

---

## Migration Guidelines for Agents

When implementing changes or transitioning systems:

1. **Keep `borgbackup` Package Until Repository Migration Completes**:
   - The legacy systemd units, SELinux module, and builder stage are retired, but the `borgbackup` RPM must remain installed in `Containerfile` and `build/justfile` so existing Borg repositories can be inspected and migrated.
2. **Central Databasus Opt-In**:
   - Keep `databasus.container` opt-in and bound to `127.0.0.1:4005` so only designated backup hosts run the central database backup UI.
3. **Appdata Consistency**:
   - Ensure that application quadlets and database containers expose standard dump volumes or database ports accessible by Databasus prior to filesystem snapshotting.
