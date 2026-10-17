# Backup Architecture: Current and Target State

This document outlines the backup infrastructure for hosts running images built from this repository. A migration is actively in progress to phase out Borgmatic in favor of a modern, decoupled backup strategy utilizing Restic and Databasus.

---

## Architectural Comparison

| Dimension | Current State | Target State (Migration in Progress) |
| :--- | :--- | :--- |
| **Primary Engine (Files/Appdata)** | Borgmatic (`borgbackup`) | **Restic** |
| **Primary Engine (Databases)** | Borgmatic internal database dump hooks | **Databasus** |
| **Package Management** | Compiled Python wheel via `uv` in multi-stage build | Standalone Go/Rust binaries or dedicated quadlet containers |
| **Systemd Units** | `borgmatic.service`, `borgmatic.timer` in `rootfs/common/` | User/system quadlets & restic systemd timers |
| **SELinux Integration** | Custom SELinux policy module (`build/selinux/borgmatic/`) | Standard container/system unconfined policies |
| **Repository Backend** | SSH Borg repositories / local drives | S3-compatible object storage, B2, or local storage |
| **Status** | Active / Legacy | In development / Phasing in |

---

## Current State: Borgmatic Architecture

The current backup solution relies on Borgmatic wrapper scripts and systemd orchestration:

```mermaid
flowchart TD
    Timer["rootfs/common/.../borgmatic.timer<br/>(Fires daily at 04:00)"]
    Service["rootfs/common/.../borgmatic.service<br/>(systemd-inhibit --who=borgmatic)"]
    Builder["Containerfile: borgmatic-builder stage<br/>(uv pip install --prefix=/tmp/borgmatic borgmatic)"]
    Binary["/usr/bin/borgmatic<br/>(Installed in final image /usr)"]

    Timer --> Service
    Builder --> Binary
    Service --> Binary
```

### 1. Build Stage Integration
In [Containerfile](Containerfile#L30-L35):
- A dedicated multi-stage build stage `borgmatic-builder` inherits from `base`.
- Installs `gcc` and `python3-devel`.
- Uses Astral `uv` to build Borgmatic into `/tmp/borgmatic`:
  ```dockerfile
  FROM base AS borgmatic-builder
  RUN dnf install -y gcc python3-devel && \
      mkdir /var/roothome && \
      uv pip install --prefix=/tmp/borgmatic borgmatic
  ```
- The `final` stage copies the built prefix into the root filesystem:
  ```dockerfile
  COPY --from=borgmatic-builder /tmp/borgmatic /usr
  ```
- Backed by system packages: `borgbackup`, `rclone`, and `rsync`.

### 2. Systemd Service and Timer
Installed in `rootfs/common/usr/lib/systemd/system/`:
- **`borgmatic.timer`**:
  - Triggers daily at 04:00 AM with persistence (`Persistent=true`).
  - Activates `borgmatic.service`.
- **`borgmatic.service`**:
  - Type: `oneshot`.
  - Condition: `ConditionACPower=true` (prevents battery depletion on mobile devices).
  - Security credentials: `LoadCredentialEncrypted=borgmatic.pw`.
  - Priority: `Nice=19`, `CPUSchedulingPolicy=batch`, `IOSchedulingClass=best-effort`.
  - Execution wrapper: Uses `systemd-inhibit --who="borgmatic" --what="sleep:shutdown" --why="Prevent interrupting scheduled backup" /usr/bin/borgmatic --verbosity -2 --syslog-verbosity 1` with an initial `ExecStartPre=sleep 1m` settling delay.

### 3. SELinux Policy Module
- Located in `build/selinux/borgmatic/`.
- Compiles custom SELinux policy (`borgmatic.te`, `borgmatic.fc`, `borgmatic.if`) to permit borgmatic to inspect files across varying filesystem labels and interact with system credentials.

---

## Target State: Restic + Databasus Migration

The target state decouples general filesystem and application data backups from stateful database backups.

### 1. Restic for Files and Appdata (Implemented in Base Image)
- **Purpose**: Fast, secure, deduplicated backups of host directories (`/etc`, `/var`, `/home`) and application data (`/home/*/appdata`).
- **Advantages over Borgmatic**:
  - Native Go binary (`/usr/bin/restic`, installed via EPEL in [Containerfile](Containerfile)) with no Python or C-extension runtime dependencies.
  - Native first-class support for cloud object storage (S3, Backblaze B2, MinIO, Azure) and local repositories without relying on SSH bridges or local FUSE mounts.
  - Significantly faster index traversal and snapshot operations.
- **Implementation (Shipped in Base Image)**:
  - **Package**: `restic` installed directly in the `final` stage of [Containerfile](Containerfile).
  - **Backup Wrapper**: [`rootfs/common/usr/libexec/coreos/restic-backup.sh`](../rootfs/common/usr/libexec/coreos/restic-backup.sh) (mode `0755`) loads `/etc/restic/env`, fails closed if `RESTIC_REPOSITORY` is unset, reads the encrypted systemd credential `${CREDENTIALS_DIRECTORY}/restic.pw` (or falls back to `RESTIC_PASSWORD_FILE`), auto-initializes uninitialized repositories via `restic init`, backs up `$BACKUP_PATHS` (default `/etc /var /home` plus any existing `/home/*/appdata` directories) with `--exclude-file=/etc/restic/excludes.txt` and `--host "$(hostname)"`, and applies retention pruning (`restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`).
  - **Configuration & Excludes**:
    - [`rootfs/common/etc/restic/env`](../rootfs/common/etc/restic/env) (installed to `/etc/restic/env`, mode `0600`): Secret-free configuration template defining `RESTIC_REPOSITORY=`, optional `RESTIC_PASSWORD_FILE`, `RESTIC_OPTIONS`, and `BACKUP_PATHS`.
    - [`rootfs/common/etc/restic/excludes.txt`](../rootfs/common/etc/restic/excludes.txt) (installed to `/etc/restic/excludes.txt`): Default exclusion rules for caches and ephemeral/reproducible paths (`/var/cache`, `/var/tmp`, `/var/lib/containers/storage`, `/var/lib/nix`, `/var/lib/systemd/random-seed`, `/var/lib/machine-id`, `**/.cache`, `**/lost+found`, `/nix`).
  - **Systemd Units**:
    - [`rootfs/common/usr/lib/systemd/system/restic-backup.service`](../rootfs/common/usr/lib/systemd/system/restic-backup.service) (`restic-backup.service`): `Type=oneshot` service with `ConditionACPower=true`, `LoadCredentialEncrypted=restic.pw`, `EnvironmentFile=-/etc/restic/env`, batch CPU/IO scheduling priority, `ExecStartPre=sleep 1m`, and `ExecStart=/usr/libexec/coreos/restic-backup.sh`.
    - [`rootfs/common/usr/lib/systemd/system/restic-backup.timer`](../rootfs/common/usr/lib/systemd/system/restic-backup.timer) (`restic-backup.timer`): Fires daily at `04:30:00` (`Persistent=true`), offset from Borgmatic's `04:00:00` schedule.
  - **Opt-In Activation**: `restic-backup.timer` is **not enabled by default** in the image. Nothing runs until an operator configures `/etc/restic/env`, provisions the `restic.pw` credential (via `systemd-creds encrypt`), and enables the timer (`systemctl enable --now restic-backup.timer`).

### 2. Databasus for Databases
- **Purpose**: Dedicated, isolated database dump management and snapshotting for relational engines (PostgreSQL, MySQL, SQLite, MariaDB).
- **Advantages over Borgmatic Hooks**:
  - Avoids running database client dump hooks inside the monolithic host backup process.
  - Runs as an independent container service with native database connection management, compression, verification, and rotation.
  - Consistent point-in-time recovery without locking the entire host filesystem snapshot.

---

## Migration Guidelines for Agents

When implementing changes or transitioning systems:

1. **Do Not Prematurely Remove Borgmatic Units**:
   - Both `borgmatic.service` and `borgmatic.timer` must remain intact in `rootfs/common/` until Restic and Databasus deployments are verified in production.
2. **Phase Out `borgmatic-builder`**:
   - Once all host targets switch to Restic, remove the `borgmatic-builder` multi-stage block in [Containerfile](Containerfile) and clean up `build/selinux/borgmatic/`.
3. **Appdata Consistency**:
   - Ensure that application quadlets and database containers expose standard dump volumes or database ports accessible by Databasus prior to filesystem snapshotting.
