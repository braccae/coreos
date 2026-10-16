# Nix Validation — End-to-End in Every Run Mode

This document records **how to prove Nix actually works end-to-end** in each
supported run mode, and the reproducible harness that does it. It complements
[mode-spec.md](mode-spec.md) (the normative run-mode contract) and
[testing.md](testing.md) (the test guide).

## What "works end-to-end" means here

In every mode the proof is the same concrete sequence, run **inside** the
target environment with that environment's own Nix:

1. `nix --version` — the Nix daemon/binary is present and functional.
2. `nix-channel --update` — Nix can reach and evaluate nixpkgs.
3. `nix-env -iA nixpkgs.<pkg>` — Nix can **fetch/realise** a real package
   (default `hello`, override with `PKG=`).
4. Execute the installed binary and capture its stdout — the canonical
   `Hello, world!`.

A mode **passes** only when the binary executes cleanly (`Hello, world!` for the
default package). Absence of an environment is reported as `skipped`, never as a
false pass.

## Harness layout

| File | Role |
|------|------|
| `build/scripts/validate-nix-runmodes.sh` | Orchestrator. `[app|systemd|vm|all]`. Writes `result.json` per mode. |
| `build/scripts/validate-nix-vm-ssh.sh` | Mode 3 (bootc VM). Fully **unprivileged** qemu+KVM path. |
| `build/scripts/build-nix-base-disk.sh` | Builds the qcow2 the VM mode boots. |

Evidence lands under `output/evidence/nix-{app,systemd,vm}/<UTC-timestamp>/`
(`output/` is git-ignored). Each run writes `run.log` and, on success, a final
`PASS: nix-<mode>` line.

## Modes 1 & 2 — containers

Run the orchestrator against a built image that ships the nix stack:

```bash
cd .worktrees/nix-val-runmodes
IMAGE=localhost/alma:nix-base \
    build/scripts/validate-nix-runmodes.sh app       # single-app, no systemd
IMAGE=localhost/alma:nix-base \
    build/scripts/validate-nix-runmodes.sh systemd   # rootless multi-process
```

- **app** — `podman run --rm` a one-shot container; the workload installs and
  executes the package in the container's own nix.
- **systemd** — `podman run --systemd=always`; the workload runs once the
  container's systemd is up (nix.mount active, nix-daemon.socket active).

## Mode 3 — bootc VM

### Base disk requirement (important)

The VM mode boots a **prebuilt bootc qcow2**. That base disk must contain
**both**:

1. the **nix stack** (nix RPM + `nix.mount` + `nix-daemon.socket` + the
   `build/selinux/nix` module), and
2. the **BUG-5 sshd host-key fix** (`build/selinux/sshd/*` +
   `/var/lib/sshd` `d`+`Z` tmpfiles entry) — without it `sshd` fails to start
   under SELinux enforcing and there is no way to run the workload remotely.

A nix-only image therefore cannot pass the VM mode, and an sshd-only image has
no nix. The base disk must also carry a `core` admin user whose authorized key
matches `~/.ssh/id_ed25519.pub` (see `build/config-img.toml`).

### Building the base disk

```bash
# 1. build the container image from a checkout carrying nix + the BUG-5 fix
podman build -t localhost/alma:nix-base .

# 2. BIB it to a qcow2 (config injects the core user + key)
build/scripts/build-nix-base-disk.sh localhost/alma nix-base
#   → output/alma/nix-base/qcow2/disk.qcow2
```

Already have the BUG-5-fixed image? Point straight at it:

```bash
build/scripts/build-nix-base-disk.sh localhost/alma bug5-fixed
```

### Running the VM proof

```bash
# base disk auto-resolved from the candidate list; or set it explicitly:
BASE_DISK=output/alma/nix-base/qcow2/disk.qcow2 \
    build/scripts/validate-nix-vm-ssh.sh

# via the orchestrator (same path, writes result.json):
BASE_DISK=output/alma/nix-base/qcow2/disk.qcow2 \
    build/scripts/validate-nix-runmodes.sh vm
```

The script:

1. Creates an ephemeral qcow2 overlay backed by the base disk (base untouched).
2. Boots it with `qemu-system-x86_64 -enable-kvm`, UEFI/OVMF, virtio NIC +
   host→guest port-forward, and a QGA virtio-serial channel.
3. Pushes the local ed25519 public key into the guest via QGA
   (`guest-ssh-add-authorized-keys`) — no cloud-init or console login needed.
4. SSHes in, then runs the install+execute proof above.
5. Writes evidence and exits `0` on `Hello, world!`.

`BASE_DISK` resolution order: explicit `$BASE_DISK`, then the candidate list in
the script. If nothing is readable it prints the build instructions and exits
`2` (**skipped**).

## Prerequisites

- Modes 1/2: `podman`; an image with the nix stack.
- Mode 3: `qemu-system-x86_64`, `qemu-img`, `ssh`, `python3`, OVMF firmware
  (`/usr/share/OVMF/x64/OVMF_CODE.4m.fd`), and **read/write `/dev/kvm`** for the
  invoking user. No `sudo`, no `libvirt`, no `virt-install` required.

## Verifying all modes at once

```bash
BASE_DISK=output/alma/nix-base/qcow2/disk.qcow2 \
IMAGE=localhost/alma:nix-base \
    build/scripts/validate-nix-runmodes.sh all
```

A skipped VM (exit `2`) does not fail the `all` run; a VM failure (exit `1`)
does.
