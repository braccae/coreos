# Workstation → Alma: Gap Analysis & Production Cutover Plan

**Task:** `t_372aa4f5` — Full workstation to Alma merge (merge/cutover half)
**Branch:** `feature/workstation-alma-merge` (local only; no push, no PR)
**Status:** PLAN + VERIFY complete. **The production cutover has NOT been executed.**

This document is the staged cutover plan for replacing the bazzite-based
`workstation.Containerfile` production image with the Alma-based
`workstation-alma.Containerfile`. A production machine is currently running the
bazzite image, so nothing here is executed until the operator frees the device
(see [Cutover Plan](#cutover-plan)).

---

## 1. Image naming

| Context | Reference |
| :--- | :--- |
| Canonical registry image | `ghcr.io/braccae/workstation-alma:latest` |
| Accepted equivalent form | `ghcr.io/braccae/workstation:alma` |
| Local build tag | `localhost/workstation-alma:test` |

No third name is introduced. The CI workflow
[`.github/workflows/container-workstation-alma.yml`](../.github/workflows/container-workstation-alma.yml)
already publishes `ghcr.io/braccae/workstation-alma` on `main` (tag `workstation-alma`).

---

## 2. Gap analysis: `workstation-alma` vs. bazzite `workstation`

Reference sources (read-only):
- `workstation.Containerfile` (bazzite — **frozen production file**)
- `build/justfile` (`install-*` recipes invoked by the bazzite workstation build)
- `Containerfile` (Alma base — what `workstation-alma` inherits)
- `workstation-alma.Containerfile` + `rootfs/workstation-alma/`

The bazzite workstation image pulls most of its userland from the bazzite base and
`build/justfile` recipes: `install-java`, `install-kde-utils`, `install-misc-tools`,
`install-virt-tools`, `install-dev-mode`. The Alma variant inherits a large, nearly
identical set from the Alma base image (`Containerfile` lines 39–77, 156–162) and
adds its desktop stack on top.

Legend: **covered** = present in `workstation-alma`; **missing** = present on bazzite
but absent here; **omitted** = deliberately not installed, with reason.

### 2.1 KDE Plasma desktop stack (`install-kde-utils` equivalent)

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| `plasma-workspace` | bazzite base | covered | 6.6.4 |
| `plasma-desktop` | bazzite base | covered | 6.6.4 |
| `kwin` | bazzite base | covered | 6.6.4 |
| `plasma-breeze`, `breeze-icon-theme` | bazzite base | covered | |
| `polkit-kde` | bazzite base | covered | |
| `konsole` | `install-kde-utils` | covered | |
| `kmail` | `install-kde-utils` | covered | 25.12.3 |
| `merkuro` | `install-kde-utils` | covered | |
| `yakuake` | `install-kde-utils` | covered | |
| `kde-partitionmanager` | `install-kde-utils` | covered | |
| `qt6-qtlocation` | `install-kde-utils` | covered | pulled as dep |
| `qt6-qtwebsockets` | `install-kde-utils` | covered | pulled as dep |
| `qt6-qtwebsockets-devel` | `install-kde-utils` | **missing** | -devel header; no runtime impact |
| `chromium-qt6-ui` | `install-kde-utils` | **covered (fixed)** | in EPEL 10; added this task |
| `fedora-chromium-config-kde` | `install-kde-utils` | omitted | Fedora-specific config; not in EL10 |
| `plasma-discover-flatpak` | `install-kde-utils` | omitted | Fedora packaging; flatpak/Discover unsupported on bootc |
| `plasma-discover-rpm-ostree` | `install-kde-utils` | omitted | Fedora packaging; rpm-ostree not used on Alma bootc |

### 2.2 Display manager & session

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| SDDM (Wayland) | bazzite base | covered | `sddm`, `sddm-kcm`; `rootfs/workstation-alma/etc/sddm.conf.d/10-wayland.conf` selects Wayland + `kwin_wayland` greeter |
| Graphical default target | bazzite base | covered | `systemctl set-default graphical.target` |
| Xwayland | bazzite base | covered | `xorg-x11-server-Xwayland`, `libxcvt` |
| Mesa / GL | bazzite base | covered | `mesa-dri-drivers`, `mesa-libEGL` |
| ZRAM swap | `rootfs/workstation/…/zram-generator.conf` | covered | `rootfs/workstation-alma/etc/systemd/zram-generator.conf` |

### 2.3 Audio

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| PipeWire stack | bazzite base | covered | `pipewire`, `wireplumber`, `pipewire-pulseaudio`, `pulseaudio-utils`, `alsa-utils` |

### 2.4 Virtualization (`install-virt-tools`)

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| `virt-manager` | `install-virt-tools` | covered | 5.1.0 |
| `qemu-kvm`, `qemu-img` | `install-virt-tools` | covered | |
| `qemu-tools` | `install-virt-tools` | substituted | → `qemu-kvm-tools` (EL10 name) |
| virtio-gpu GL display | `qemu-device-display-virtio-gpu-gl`, `…-pci-gl` | substituted | → `qemu-kvm-device-display-virtio-gpu`, `…-pci` (EL10 names) |
| virtio-gpu | `qemu-device-display-virtio-gpu` | covered | |
| SPICE char/UI | `qemu-char-spice` | substituted | → `qemu-kvm-ui-spice` (EL10 name) |
| audio-pipewire | `qemu-audio-pipewire` | substituted | → `qemu-kvm-audio-pa` (pulled by `qemu-kvm`) |
| usb-redirect | `qemu-device-usb-redirect` | covered | `qemu-kvm-device-usb-redirect` |
| OpenGL UI | — | covered | `qemu-kvm-ui-opengl` |
| `qemu-guest-agent` | `workstation.Containerfile` | covered | inherited from base (`Containerfile` line 40) |

### 2.5 Dev mode (`install-dev-mode`)

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| `code` (VS Code) | `install-dev-mode` | covered | MS repo key imported in Containerfile |
| `gh` (GitHub CLI) | `install-dev-mode` | covered | from base gh-cli repo |
| `nodejs`, `nodejs-npm` | `install-dev-mode` | covered | inherited from base |
| `pnpm` | `install-dev-mode` | covered (non-RPM) | installed globally via `npm install -g pnpm` (not in EL10 RPM repos) |

### 2.6 Miscellaneous tools (`install-misc-tools`) & base

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| `git`, `tmux`, `sqlite`, `git` | `install-misc-tools` | covered | inherited from base |
| `samba`, `samba-common-tools`, `samba-usershares` | `install-misc-tools` | covered | inherited from base |
| `tuned`, `realmd`, `sssd` | `install-misc-tools` | covered | inherited from base |
| `rclone` | `install-misc-tools` | covered | installed by base via rclone install script |
| `borgbackup` | `install-misc-tools` | covered | inherited from base |
| `borgmatic` | `install-misc-tools` | covered | installed by base via `uv pip` into `/usr` |
| `rsync` | `install-misc-tools` | covered | inherited from base |
| `bat`, `mpv`, `waypipe` | `install-misc-tools` | covered | installed by `workstation-alma.Containerfile` |
| `zsh` | `install-misc-tools` | covered | inherited from base |
| `tailscale` | `install-misc-tools` | covered | inherited from base; `tailscaled` enabled by base |
| `sqlite-devel` | `install-misc-tools` | **covered (fixed)** | in AppStream; added this task |
| `chromium`, `chromium-headless`, `chromedriver` | `install-misc-tools` | **covered (fixed)** | in EPEL 10; added this task |
| `bees` | `install-misc-tools` | omitted | btrfs dedup; not in EPEL 10 |
| `ghostty` | `install-misc-tools` | omitted | Fedora COPR only; no EL10 package |
| `input-leap` | `install-misc-tools` | omitted | not in EPEL 10 or RPMFusion EL10 |
| `java-21-openjdk` | `install-java` | covered | 21.0.12 |
| `XIVLauncher` | `install-game-mode` | omitted | Fedora game COPR only (recipe not called by bazzite workstation either) |
| `just` | `workstation.Containerfile` | covered | inherited from base |

### 2.7 ZFS / Nix / kernel modules

| Feature | Bazzite source | Alma status | Notes |
| :--- | :--- | :--- | :--- |
| ZFS kernel modules | `kmods` image + `depmod` in `workstation.Containerfile` | covered | Alma base ingests `/zfs/alma/${TARGETARCH}/` from `kmods` (`Containerfile` lines 112–137) |
| `modinfo` build fallback | — | covered (Alma-specific) | `rootfs/workstation-alma/usr/local/bin/modinfo` resolves in-image kernel when host kernel is absent |
| dracut initramfs regen | `workstation.Containerfile` lines 44–48 | covered | done in base (`Containerfile` lines 143–147) |
| Nix + persistent `/nix` | — | not included | Nix ships only in the `dx` image (`just setup-nix` opts in); `workstation-alma` no longer inherits it |

### 2.8 Overlay differences (bazzite vs. Alma `rootfs/`)

| File | bazzite `rootfs/workstation/` | Alma `rootfs/workstation-alma/` |
| :--- | :--- | :--- |
| `etc/systemd/zram-generator.conf` | present | present (identical intent) |
| `usr/lib/ostree/prepare-root.conf` | present | **absent** — Alma uses the base's `rootfs/non_btrfs/usr/lib/ostree/prepare-root.conf` |
| `usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy` | present | present (trailing-newline-only diff) |
| `etc/sddm.conf.d/10-wayland.conf` | — | present (Alma-specific) |
| `usr/local/bin/modinfo` | — | present (Alma-specific build fallback) |

The `prepare-root.conf` difference is expected: the bazzite workstation layers on
btrfs (`rootfs/btrfs_config/`), while `workstation-alma` inherits the base's
XFS/ext4-oriented `rootfs/non_btrfs/` config. The Alma variant does not ship a
btrfs composefs layout — see [Open items](#6-open-items).

### 2.9 Summary of gaps closed in this task

Added to `workstation-alma.Containerfile` (all confirmed present in EPEL 10 / AppStream):

- `chromium`, `chromium-headless`, `chromedriver`, `chromium-qt6-ui`
- `sqlite-devel`

The C8 note claiming "chromium-qt6-ui … omitted; Fedora-specific configs" was
**inaccurate** — `chromium`, `chromium-headless`, `chromedriver` and `chromium-qt6-ui`
are all published in EPEL 10 as `155.0.8059.39-1.el10_2`. Only
`fedora-chromium-config-kde` is genuinely Fedora-only.

### 2.10 Remaining gaps (documented, not fixed)

| Gap | Reason not fixed |
| :--- | :--- |
| `ghostty` | No EL10 package (Fedora COPR only). Would require a third-party COPR. |
| `input-leap` | Not packaged in EPEL 10 or RPMFusion EL10. |
| `bees` | Not in EPEL 10. |
| `plasma-discover-flatpak` / `plasma-discover-rpm-ostree` | Fedora packaging; flatpak/rpm-ostree not supported on Alma bootc. |
| `fedora-chromium-config-kde` | Fedora-specific config; not in EL10. |
| `qt6-qtwebsockets-devel` | -devel header; no runtime consumer on the workstation. |
| `XIVLauncher` | Fedora game COPR only; not part of the bazzite workstation build either. |

None of these require touching a frozen bazzite file; all are genuine EL10 packaging
absences. Closing them would mean adding a third-party COPR/RPM source — a policy
decision for the operator, not a trivial substitution.

---

## 3. Cutover Plan

> **This plan is NOT executed here.** It runs only after the operator confirms the
> production device is free to switch. Every command below is to be run **on the
> production workstation**, as `root` (`sudo -i`).

### 3.1 Pre-switch verification checklist (run on the device, before switching)

1. **Image published and pullable** — the Alma image must exist in the registry
   before the device can switch:
   ```bash
   # from any host with podman + registry access
   podman pull ghcr.io/braccae/workstation-alma:latest
   podman image inspect ghcr.io/braccae/workstation-alma:latest --format '{{.Digest}}'
   ```
   For a local-only rehearsal (no registry), build and load the image manually:
   ```bash
   podman build -f workstation-alma.Containerfile -t localhost/workstation-alma:test .
   ```
2. **Lint is clean** — 9/10 checks pass (4 non-blocking warnings), matching §5:
   ```bash
   podman run --entrypoint bootc localhost/workstation-alma:test container lint
   ```
3. **Key userland present** in the image:
   ```bash
   podman run --entrypoint rpm localhost/workstation-alma:test -q \
       plasma-workspace sddm kwin virt-manager qemu-kvm java-21-openjdk code gh chromium
   # NOTE: `core` is NOT baked into the container image (only webtop bakes a user).
   # It is created at VM image build time via build/config-img.toml, so `id core`
   # inside the container is expected to fail. Verify it on the booted VM instead.
   ```
4. **Current production state captured** (for rollback):
   ```bash
   bootc status                      # note the current image ref/digest and deployment
   ostree admin status               # deployment index + checksums
   ```
5. **Back up anything uncommitted** — user data lives in `/var` and `/home`, which
   survive an image switch; but confirm:
   - ZFS pools imported and healthy: `zpool status`
   - `/home/core` intact
   - No in-flight work you cannot redo.

### 3.2 Switch command

`bootc switch` stages the new image as the next deployment and (by default) reboots
into it. The Alma variant's `ENTRYPOINT`/kernel/module layout differs from bazzite, so
the switch also pulls the Alma kernel + ZFS kmods bundled in the image.

```bash
# On the production device:
sudo bootc switch ghcr.io/braccae/workstation-alma:latest
```

To stage without an immediate reboot (verify the deployment first):

```bash
sudo bootc switch --transport registry ghcr.io/braccae/workstation-alma:latest
# ...then inspect and reboot manually:
sudo bootc status
sudo systemctl reboot
```

> Note on the accepted equivalent name: if the image is published as
> `ghcr.io/braccae/workstation:alma`, the identical command is
> `sudo bootc switch ghcr.io/braccae/workstation:alma`.

### 3.3 Post-reboot verification

Log in on the console (SDDM Wayland session) and confirm each subsystem:

| Check | Command / action | Expected |
| :--- | :--- | :--- |
| Deployment switched | `bootc status` | Active image = `workstation-alma` |
| Graphical boot | console | SDDM greeter on Wayland; Plasma 6 session starts |
| Compositor | `echo $XDG_SESSION_TYPE` (in session) | `wayland` |
| ZFS | `zpool status`, `zfs list`, `modinfo zfs` | pools imported/healthy; module loaded |
| Kernel/modules | `uname -r` vs `ls /usr/lib/modules` | booted kernel has modules (kmods match) |
| Virtualization | open `virt-manager`, start a test VM | libvirt/qemu stack works; virtio-gpu/SPICE display |
| Audio | `wpctl status` / play test sound | PipeWire sink present |
| Nix | `nix --version`, `nix shell nixpkgs#hello -c hello` | store works; `/nix` persisted |
| Network/Tailscale | `tailscale status` | node online |
| Dev tooling | `code --version`, `gh --version`, `pnpm --version` | present |
| Chromium | launch `chromium` | launches (added this task) |
| User identity | `id core` (on the booted VM) | uid=1000, groups wheel/video/render — `core` exists only **after** the VM image is built (config-img.toml), not in the container image itself |

### 3.4 Rollback path

If the Alma image fails to boot or a subsystem is broken, roll back to the previous
deployment — no data is lost because the prior deployment remains on disk as an
`ostree` deployment:

```bash
# From the Alma deployment:
sudo bootc status                 # identify the previous (bazzite) deployment index
sudo ostree admin status          # list deployments; note the index of the bazzite one
```

**Option A — boot the previous deployment once (non-destructive):**
```bash
sudo ostree admin deploy --retain <bazzite-checksum>   # if not already present
sudo ostree admin set-default <index-of-bazzite-deployment>
sudo systemctl reboot
```

**Option B — switch the default image back to the bazzite reference:**
```bash
sudo bootc switch ghcr.io/braccae/workstation:latest
# (the published bazzite workstation tag; verify the exact ref from `bootc status`
#  captured in step 3.1.4 before switching away)
sudo systemctl reboot
```

If neither deployment boots, the device can be recovered by booting the previous
kernel from the bootloader's ostree menu entry and rolling back from there.

---

## 4. Files touched by this task

| File | Change |
| :--- | :--- |
| `docs/workstation-alma-merge.md` | **new** — this document |
| `workstation-alma.Containerfile` | added `chromium`, `chromium-headless`, `chromedriver`, `chromium-qt6-ui`, `sqlite-devel`; corrected the omission note |

Follow-up `t_0c8501b9` (drop the baked-in `core` user — only webtop bakes a user):

| File | Change |
| :--- | :--- |
| `workstation-alma.Containerfile` | removed the `# --- core user ---` block (`useradd`/`chpasswd`/`sudoers.d/core`/`/home/core`); replaced with a comment noting the user is provisioned at VM image build time via `build/config-img.toml` |
| `docs/workstation-alma-merge.md` | corrected the "User identity" verification row and the §5.4 "Core user" evidence; dropped `core` from the sysusers lint warning |

No frozen file was modified: `workstation.Containerfile` and `rootfs/workstation/`
are untouched. Nothing was pushed and no PR was opened.

---

## 5. Build & verification evidence

Raw evidence is in [`build.log`](../build.log) in the worktree root. This build
reflects the follow-up `t_0c8501b9` change that dropped the baked-in `core` user.

### 5.1 Build

```bash
$ podman build -f workstation-alma.Containerfile -t localhost/workstation-alma:test .
...
STEP 9/9: ENTRYPOINT ["/usr/lib/systemd/systemd"]
COMMIT localhost/workstation-alma:test
--> 90f6feab80c2
Successfully tagged localhost/workstation-alma:test
```

Resulting image:
```
Id:     90f6feab80c2c70cdb5f9e016634ea9a66f04ee8c5d866285a8d04b276e815fa
Digest: sha256:de1d0ed0a994106bb1258aa891f30ea7b5a9e2ec44c73822c37ccb629201c0f1
Size:   8516116099 (8.5 GB)
Created: 2026-10-16 23:35:41 UTC
```

(The build is now 9 steps rather than 11: removing the baked-in `core` user dropped
two `RUN` layers.)

### 5.2 Lint

```bash
$ podman run --entrypoint bootc localhost/workstation-alma:test container lint
Lint warning: nonempty-run-tmp: Found content in runtime-only directories (/run, /tmp)
Lint warning: sysusers: /etc/passwd|group entries without systemd sysusers.d (avahi, usbmuxd)
Lint warning: var-log: non-empty logfiles (/var/log/dnf*.log)
Lint warning: var-tmpfiles: /var content missing tmpfiles.d entries
Checks passed: 9
Checks skipped: 1
Warnings: 4
lint_exit=0
```

9/10 checks pass, 4 warnings — all non-blocking (same profile as C8). The warnings
are base-image hygiene items (runtime dirs, dnf logs, tmpfiles), not defects in the
workstation layer.

### 5.3 Package presence

```bash
$ podman run --entrypoint rpm localhost/workstation-alma:test -q \
    plasma-workspace sddm kwin virt-manager qemu-kvm java-21-openjdk code gh \
    chromium chromium-headless chromedriver chromium-qt6-ui sqlite-devel
plasma-workspace-6.6.4-1.el10_2.x86_64
sddm-0.21.0-9.el10_1.x86_64
kwin-6.6.4-2.el10_2.x86_64
virt-manager-5.1.0-2.el10.noarch
qemu-kvm-10.1.0-16.el10_2.5.alma.1.x86_64
java-21-openjdk-21.0.12.1.1-1.2.el10.alma.1.x86_64
code-1.142.0-1792035085.el8.x86_64
gh-2.97.0-2.el10_2.x86_64
chromium-155.0.8059.39-1.el10_2.x86_64
chromium-headless-155.0.8059.39-1.el10_2.x86_64
chromedriver-155.0.8059.39-1.el10_2.x86_64
chromium-qt6-ui-155.0.8059.39-1.el10_2.x86_64
sqlite-devel-3.46.1-6.el10_2.x86_64
```

### 5.4 Core user

The container image bakes NO user — `core` is provisioned at VM image build time
via `build/config-img.toml` (`[[customizations.user]] name = "core"`, groups
`wheel`, ssh key), matching how the base image ships no user. The `id core`
check is therefore expected to FAIL inside the container image:

```bash
$ podman run --entrypoint id localhost/workstation-alma:test core
id: 'core': no such user
$ echo $?
1
```

On the booted VM image, `id core` should report uid=1000, groups wheel/video/render.

### 5.5 Non-RPM toolchains present

```bash
$ podman run --entrypoint rclone localhost/workstation-alma:test version
rclone v1.75.2  (almalinux 10.2)
$ podman run --entrypoint borgmatic localhost/workstation-alma:test --version
2.1.10
$ podman run --entrypoint pnpm localhost/workstation-alma:test --version
12.11.2
$ podman run --entrypoint nix localhost/workstation-alma:test --version
nix (Nix) 2.31.5
```

### 5.6 Default target & module resolution

```bash
$ podman run --entrypoint systemctl localhost/workstation-alma:test get-default
graphical.target
$ podman run --entrypoint /usr/local/bin/modinfo localhost/workstation-alma:test -n zfs
/lib/modules/6.12.0-211.65.1.el10_2.x86_64/extra/zfs/zfs.ko
```

---

## 6. Open items

1. **Cutover not executed** — awaiting operator confirmation that the production
   device is free. See §3.
2. **Registry tag decision** — `ghcr.io/braccae/workstation-alma:latest` is the
   working name; the merge to `main` (and thus CI publication) is gated on the same
   approval. Do not merge before the device is free.
3. **Rootfs layout** — `workstation-alma` uses the base's XFS/ext4 `rootfs/non_btrfs/`
   prepare-root config. If the production device's root filesystem is btrfs (as the
   bazzite workstation assumed), the cutover must either install onto XFS or a
   btrfs-capable prepare-root config must be added. **Confirm the production device's
   root filesystem before switching.**
4. **Remaining EL10 packaging gaps** — see §2.10 (ghostty, input-leap, bees,
   plasma-discover-*). Closing them needs a third-party repo decision.
5. **ARM/kmods and Nix-validation siblings** — tracked on separate cards; full
   parity for non-x86_64 and Nix run-mode validation is outside this card's scope.
