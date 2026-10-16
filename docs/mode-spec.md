# Run-Mode Specification

This document is the **normative acceptance contract** for the four execution
modes this repository's images must satisfy. [testing.md](testing.md) describes
*what* each mode is; this document fixes *exactly* how each mode is executed and
*exactly* what constitutes a pass. The local harness (EPIC B / task B3) must
implement recipes that satisfy every clause below verbatim.

A mode **passes** only when every numbered pass condition in its section is met.
Each mode must emit its evidence under `output/evidence/<mode>/` so results are
machine-checkable and reproducible across runs.

---

## Common Conventions

These apply to all four modes.

- **Image under test.** Recipes take an image reference argument. Default to the
  locally built tag `localhost/alma:latest`; the published tag
  `ghcr.io/braccae/alma:latest` is accepted as an override for release validation.
- **Evidence root.** `output/evidence/` is created by each recipe. Evidence is
  never committed; the `output/` tree is git-ignored.
- **Exit contract.** Every recipe exits `0` **only** when all pass conditions for
  that mode hold. Any failed condition must cause a non-zero exit and a line
  beginning `FAIL:` naming the condition.
- **Report contract.** On success each recipe prints a final line
  `PASS: <mode> <image>` and writes a `result.json` containing at minimum:
  `{"mode": "...", "image": "...", "started": "<ISO8601>", "ended": "<ISO8601>", "result": "pass", "conditions": {"<id>": "pass|fail|skipped"}}`.
- **Condition IDs.** Each pass condition is numbered per mode; the numbers below
  are the canonical IDs (e.g. `bootc-vm.2`) used in `result.json`.

---

## Mode 1 — `bootc-vm`

**Runtime:** Full OS in a virtual machine; UEFI firmware boots the built
`.qcow2` disk image. **Container:** N/A (bare-metal-equivalent VM).

### Exact commands

```bash
# 1. Build the bootable qcow2 for the image under test (rootful; needs sudo).
just build-disk-image alma latest          # -> output/alma/latest/qcow2/disk.qcow2

# 2. Boot the image headless and run the automated checks.
just test-vm-bootc alma latest             # B3 recipe to implement
```

`test-vm-bootc <image> <tag> [memory=2048] [vcpus=2]` must:

1. Copy the qcow2 to a libvirt-managed path (or boot directly with
   `qemu-system-x86_64`) using **UEFI** firmware (OVMF), matching the existing
   `virt-install ... --boot uefi` invocation in [justfile](../justfile#L169).
2. Attach a virtio NIC on the `default` libvirt network and a serial console.
3. Seed the `core` user's authorized key from the image's cloud-init/key material
   so the probe can SSH in non-interactively.
4. Poll SSH on the DHCP-assigned address until the `core` login succeeds (timeout
   `VM_BOOT_TIMEOUT`, default 300 s).
5. Run the probe commands below over SSH and capture their output.
6. Tear the VM down and remove its storage on exit (`trap ... EXIT INT TERM`).

### Pass conditions

| ID | Condition | Probe (run over SSH as `core`) | Pass when |
| :-- | :--- | :--- | :--- |
| `bootc-vm.1` | UEFI boot to login | console/serial log | bootloader runs; kernel + initramfs execute; no `Kernel panic` |
| `bootc-vm.2` | System target reached | `systemctl is-system-running --wait` | prints `running` or `degraded` |
| `bootc-vm.3` | No failed units | `systemctl --failed --no-legend` | no units listed whose names are not in the expected-degradation allowlist |
| `bootc-vm.4` | Console reachable | serial log | an interactive `login:` prompt appears |
| `bootc-vm.5` | Network + SSH | `ip -4 addr show` ; successful SSH | interface has a DHCP IPv4 lease; `core` authenticates by key |
| `bootc-vm.6` | bootc status clean | `bootc status --json` | exit 0; JSON parses; a booted deployment is present |
| `bootc-vm.7` | kmods loaded (ZFS images only) | `lsmod \| grep -c zfs` | ≥ 1; **skipped** (recorded `skipped`) for non-kmod images |

### Evidence artifact

`output/evidence/bootc-vm/<UTC-timestamp>/` containing:
`serial.log`, `systemctl-status.txt`, `failed-units.txt`, `ip-addr.txt`,
`bootc-status.json`, `lsmod-zfs.txt`, and `result.json`.

### Notes / constraints

- Local default is **2048 MB RAM / 2 vCPUs**; recipes must accept overrides
  (`memory`, `vcpus`) without changing the defaults.
- The existing interactive `just test-vm` stays as-is; `test-vm-bootc` is the
  automated, exit-code-driven counterpart.
- Boot time on TCG (no nested virt) is long — set the default timeout generously.

---

## Mode 2 — `rootless-systemd`

**Runtime:** `podman run --systemd=always` as an unprivileged user; systemd runs
as PID 1 inside the container. **Reference workload:** the webtop container
(port 3000 / Selkies).

### Exact commands

```bash
# Run as the unprivileged user `pants` (NOT root, NOT with sudo).
podman run -d \
    --name mode2-systemd \
    --systemd=always \
    --device /dev/dri \
    -p 3000:3000 \
    localhost/alma:latest

# Probe while it is up.
podman exec mode2-systemd systemctl is-system-running --wait
podman inspect mode2-systemd --format '{{.HostConfig.Privileged}}'
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
podman exec mode2-systemd systemctl --failed --no-legend

# Teardown.
podman rm -f mode2-systemd
```

A `just test-rootless-systemd <image>` recipe must run the above sequence and
implement the pass conditions.

### Pass conditions

| ID | Condition | Pass when |
| :-- | :--- | :--- |
| `rootless-systemd.1` | No privileged flag | `podman inspect ... .HostConfig.Privileged` == `false` |
| `rootless-systemd.2` | systemd is PID 1 | `podman exec ... ps -o comm= -p 1` == `systemd` |
| `rootless-systemd.3` | systemd reaches a target | `systemctl is-system-running --wait` ∈ {`running`,`degraded`} |
| `rootless-systemd.4` | No unexpected failed units | `systemctl --failed --no-legend` empty (modulo allowlist) |
| `rootless-systemd.5` | Exposed port binds | `curl http://127.0.0.1:3000/` returns an HTTP status (any 2xx/3xx/401); connection refused = fail |
| `rootless-systemd.6` | Unprivileged start | the run command itself contains no `--privileged` and the invoking UID ≠ 0 |

### Evidence artifact

`output/evidence/rootless-systemd/<UTC-timestamp>/` containing:
`podman-inspect.json`, `systemctl-status.txt`, `failed-units.txt`, `port-probe.txt`,
`ps-pid1.txt`, and `result.json`.

### Notes / constraints

- `/dev/dri` is required by the reference workload; recipes must tolerate its
  absence by falling back to a run without `--device /dev/dri` and marking the
  GPU condition `skipped` (not failed).
- Requires subordinate UID/GID ranges to be configured for the invoking user
  (`/etc/subuid`, `/etc/subgid`); a missing range is a setup error, not a mode
  failure — the recipe must fail fast with a clear message.

---

## Mode 3 — `rootless-app`

**Runtime:** A single process in a rootless container, **no init**, no systemd.
**Reference workload:** an arbitrary command passed to the image.

### Exact commands

```bash
# Run as the unprivileged user; no init, no systemd.
podman run --rm localhost/alma:latest <command>

# Signal handling check: start a long-running command, then SIGTERM it.
podman run --rm --name mode3-app -d localhost/alma:latest sleep 300
podman kill --signal SIGTERM mode3-app        # expect prompt, clean stop
podman wait mode3-app ; echo "exit=$?"        # expect 0 or 143 (SIGTERM)
```

A `just test-rootless-app <image> [command="echo ok"]` recipe must run the above
and implement the pass conditions.

### Pass conditions

| ID | Condition | Pass when |
| :-- | :--- | :--- |
| `rootless-app.1` | No init as PID 1 | `podman exec ... ps -o comm= -p 1` is the passed command (or its direct exec), **not** `systemd`/`/sbin/init` |
| `rootless-app.2` | Clean exit | `podman run --rm ... <cmd>` exit code == `0` for the smoke command |
| `rootless-app.3` | Signal propagation | `SIGTERM` stops the long-running command within `APP_STOP_TIMEOUT` (default 30 s) with exit `0` or `143`, no zombie children |
| `rootless-app.4` | Logs stream | stdout/stderr of the command appear in `podman logs` / terminal capture |

### Evidence artifact

`output/evidence/rootless-app/<UTC-timestamp>/` containing:
`smoke-exit.txt`, `signal-exit.txt`, `pid1.txt`, `logs.txt`, and `result.json`.

### Notes / constraints

- This is the lowest-privilege baseline; if a workload needs `--privileged` or an
  init, it belongs in mode 2 or 4, not here.

---

## Mode 4 — `rootless-multi`

**Runtime:** Multi-process container / nested container runtime under an
unprivileged user, using user namespaces, subuid/subgid, and **fuse-overlayfs**
storage. **Reference workload:** the `dx` developer image
(`rootfs/common/etc/containers/containers.conf.d/20-nested.conf`).

### Exact commands

```bash
# 1. One-time host setup (rootful): provision the unprivileged user.
sudo /usr/sbin/setup-podman-user pants 1000     # creates subuid/subgid, enables linger

# 2. Run the multi-process image as that user.
podman run -d \
    --name mode4-multi \
    --systemd=always \
    localhost/alma:latest

# 3. Verify fuse-overlayfs storage mounts without permission denials.
podman exec mode4-multi sh -c 'podman info --format "{{.Store.GraphDriverName}}"'
podman exec mode4-multi sh -c 'mount | grep fuse-overlayfs'

# 4. Nested container spawn inside the user session.
podman exec mode4-multi sh -c 'podman run --rm localhost/alma:latest echo nested-ok'

# 5. User quadlets run concurrently.
podman exec mode4-multi sh -c 'systemctl --user is-active podman-auto-update.timer'

# Teardown.
podman rm -f mode4-multi
```

A `just test-rootless-multi <image>` recipe must run the above and implement the
pass conditions. The image under test must ship
`/etc/containers/containers.conf.d/20-nested.conf`
(`label=false`, `cgroup_manager="cgroupfs"`) and the `setup-podman-user` helper.

### Pass conditions

| ID | Condition | Pass when |
| :-- | :--- | :--- |
| `rootless-multi.1` | fuse-overlayfs storage | `podman info` graph driver == `fuse-overlayfs`; no `operation not permitted` in `mount` output |
| `rootless-multi.2` | Subuid/subgid present | invoking user has an entry in `/etc/subuid` and `/etc/subgid` |
| `rootless-multi.3` | Nested container runs | the inner `podman run ... echo nested-ok` prints `nested-ok` and exits 0 |
| `rootless-multi.4` | User lingering | `loginctl show-user <user> -P Linger` == `yes` |
| `rootless-multi.5` | Concurrent user services | all expected user quadlets report `active` |

### Evidence artifact

`output/evidence/rootless-multi/<UTC-timestamp>/` containing:
`podman-info.txt`, `mount.txt`, `nested-run.txt`, `linger.txt`, `quadlet-units.txt`,
`setup-podman-user.log`, and `result.json`.

### Notes / constraints

- Requires `/dev/fuse` and a kernel with user-namespace support; absence is a
  capability error and must be reported as such (non-zero exit, `FAIL:` line).
- The `cgroupfs` + `label=false` contract is mandatory for nested storage to work
  without SELinux/cgroup denials.

---

## Condition-ID Index (for the harness)

```
bootc-vm.1 .. bootc-vm.7
rootless-systemd.1 .. rootless-systemd.6
rootless-app.1 .. rootless-app.4
rootless-multi.1 .. rootless-multi.5
```

B3's recipes must populate `result.json.conditions` using these exact keys so the
EPIC B test matrix can aggregate results mechanically.
