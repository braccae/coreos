# Webtop: Flatpak, AppImage and GPU acceleration

The `webtop` image streams a KDE Plasma session with Selkies 2.1. Selkies/pixelflux
owns the outer Wayland compositor (`wayland-1`), `kwin_wayland --xwayland` runs
nested on it (`wayland-0` + Xwayland), and Plasma runs inside that session. A
small nginx reverse proxy serves the dashboard and websocket on port 3000.

Everything in this document is shipped with the image or with this repository.
The image never downloads helper scripts at runtime; the only network activity is
the normal package/app installation you perform yourself.

---

## 1. Running the container

```bash
podman run -d \
  --name webtop \
  --systemd=always \
  --device /dev/dri \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --cap-add NET_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --security-opt unmask=all \
  --volume webtop-home:/home/webtop \
  --volume webtop-flatpak:/var/lib/flatpak \
  -p 3000:3000 \
  ghcr.io/braccae/webtop:latest
```

| Flag | Why |
| --- | --- |
| `--device /dev/dri` | GPU render node for capture/encode (AMD, Intel, virtio-gpu/virgl). Omit for software rendering. |
| `--device /dev/fuse` | AppImage self-mounting. |
| `--cap-add SYS_ADMIN` | FUSE mounting (AppImages) needs it in the container's user namespace; `fusermount3` is setuid so the unprivileged session can use it. `--privileged` is **not** required. |
| `--cap-add NET_ADMIN` | Lets NetworkManager own the pasta tap instead of only *assuming* it, so the desktop network indicator reports a real connection. See [Network indicator](#network-indicator). |
| `--security-opt seccomp=unconfined` | `bwrap` must create user/PID namespaces (blocked by the default seccomp profile). |
| `--security-opt label=disable` | `bwrap` cannot mount `devpts`/`proc` under the container SELinux label. |
| `--security-opt unmask=all` | Podman's masked `/proc` paths prevent `bwrap` from mounting a fresh `/proc` inside its sandbox. |

The same settings are in the [`webtop.container`](../webtop.container) quadlet
(`AddDevice`, `AddCapability`, `SecurityLabelDisable`, volumes).

Verify the graphics stack inside the running container:

```bash
podman exec webtop webtop-gpu-report
```

### Remote access

The dashboard uses `VideoDecoder`, which browsers only expose in a **secure
context**. `http://localhost:3000` works, but a plain-HTTP visit to a remote
host shows "This application requires a secure connection (HTTPS)". Either
terminate HTTPS in front of the container or use an SSH tunnel:

```bash
ssh -N -L 127.0.0.1:3000:127.0.0.1:3000 user@host
# then browse http://127.0.0.1:3000
```

---

## 2. Flatpak

The image ships `flatpak`, the system-wide `flathub` remote and the desktop
portals (`xdg-desktop-portal`, `-kde`, `-gtk`). The session's `XDG_DATA_DIRS`
includes the Flatpak export directories, so installed applications appear in the
KDE menu.

```bash
# inside the container (system install; needs root)
podman exec -it webtop sudo flatpak install -y flathub org.kde.kcalc

# or from the streamed desktop's Konsole
sudo flatpak install -y flathub org.kde.kcalc
flatpak run org.kde.kcalc
```

Persistence:

* system installs live in `/var/lib/flatpak` → volume `webtop-flatpak`
* `flatpak install --user` installs live in the home volume (`webtop-home`)

Without `--cap-add SYS_ADMIN` + `--security-opt label=disable` Flatpak fails at
launch with:

```text
bwrap: Creating new namespace failed: Operation not permitted
```

### Verification

1. `flatpak install -y flathub org.kde.kcalc`
2. Launch it from the KDE menu (or `flatpak run org.kde.kcalc`).
3. The calculator window must render in the streamed desktop.
4. Restart the container (`podman restart webtop`) and confirm the app is still
   listed and still launches.

---

## 3. AppImage

`libfuse.so.2`, `fuse3` and `fusermount3` are shipped. Use the wrapper so the
AppImage still starts when FUSE is not available:

```bash
webtop-appimage-run ~/Downloads/My.AppImage --some-flag
```

The wrapper mounts through FUSE when `/dev/fuse` exists and otherwise re-executes
the AppImage with `APPIMAGE_EXTRACT_AND_RUN=1` (slower start, no self-mount).

Direct execution also works when the container has `/dev/fuse`:

```bash
chmod +x ~/Downloads/My.AppImage
~/Downloads/My.AppImage
```

---

## 4. GPU acceleration

### AMD / Intel passthrough

Pass the render node and make sure the container user can read it:

```bash
podman run ... --device /dev/dri ...
```

`renderD*` is usually mode `0666`; `card*` is `0660` and group-owned, so if KWin
cannot open it add the host render group with `--group-add keep-groups` (rootless)
or the numeric group id.

The image already ships the Mesa drivers relevant to this:

* `radeonsi_dri.so` / `radeonsi_drv_video.so` (AMD OpenGL + VA-API)
* `virtio_gpu_dri.so` / `virtio_gpu_drv_video.so` (QEMU virtio-gpu / virgl)
* `mesa-vulkan-drivers`, `vulkan-loader`, `vulkan-tools`
* `libva`, `libva-utils` (`vainfo`)

Selkies selects hardware encoding automatically when a render node exists; the
launcher only sets `SELKIES_USE_CPU=true` when `/dev/dri/renderD128` is absent.
Look for `no hardware encoder opened` in `/tmp/webtop.log` to confirm a fallback
to software encoding.

For ROCm/OpenCL workloads, additionally pass `/dev/kfd`:

```bash
podman run ... --device /dev/dri --device /dev/kfd ...
```

### Verify

```bash
podman exec webtop webtop-gpu-report
```

Expected on a working AMD setup: `renderD128 (read/write)`, a `radeonsi` Vulkan
device, and `VAProfileH264…`/`VAProfileHEVC…` entries. `llvmpipe` / `virtio_gpu`
means software rendering.

### virgl (QEMU)

virgl gives a VM an accelerated virtio-gpu render node. Launch QEMU with a GL
display and the virtio-gpu-gl device, e.g.:

```bash
qemu-system-x86_64 \
  -enable-kvm -m 8192 -smp 4 \
  -device virtio-vga-gl \
  -display egl-headless,rendernode=/dev/dri/renderD128 \
  -drive file=webtop.qcow2,if=virtio,format=qcow2
```

or, for an interactive window on a machine with a GPU:

```bash
qemu-system-x86_64 -enable-kvm -m 8192 -smp 4 \
  -device virtio-vga-gl -display gtk,gl=on \
  -drive file=webtop.qcow2,if=virtio,format=qcow2
```

Requirements: `virglrenderer` on the host, a host GPU, and `-device virtio-vga-gl`
(not plain `virtio-vga`). Inside the guest, `dmesg | grep virtio_gpu` should show
`+virgl`, and the webtop container started with `--device /dev/dri` then reports a
`virtio_gpu`/virgl renderer instead of `llvmpipe` in `webtop-gpu-report`.

---

## 5. Known limitations

### Multi-monitor / "Add screen"

The session runs KWin nested on Selkies' built-in compositor. Adding a display
asks KWin for a `zkde_screencast_unstable_v1` virtual output, and KWin refuses
it when it is nested (`virtual screen 'SELKIES-2' refused: Could not find
output`). The screen-settings section is therefore hidden in the dashboard
instead of offering a button that always errors.

Alternatives that were evaluated:

* Point Selkies at KWin with `--wayland-host-display=wayland-0` and run KWin
  with `--virtual`: Selkies still starts and captures its own `wayland-1`
  compositor, so the stream shows an empty surface. Not viable as-is.
* Use a labwc session compositor with the linuxserver IPC patch
  (`labwc.sock`), which is what the `ADD_SCREEN` path expects. This was tested
  (Phase 0, wlroots 0.19.3 + labwc 0.9.7 + Selkies patches): `ADD_SCREEN`
  succeeds and a second capture starts, but the second screen stays black.
  KWin's Wayland backend creates exactly one host toplevel (`--output-count`)
  and never creates one for an output added later, so the new labwc output can
  only show an empty desktop. labwc outputs also leak (`WL-2`…`WL-6`) because
  Selkies bookkeeping queries KWin, which cannot see them. Keeping KWin nested
  under any compositor therefore cannot give a usable second screen.

### Network indicator

The tray icon and the `plasma-nm` popup follow NetworkManager's device state.
Inside a rootless container the uplink is a pasta **tap** (`type tun`, and a
`veth` in rootful/netavark pods). Stock Plasma 6 (plasma-nm 6.7.5) ignores both
device types, so it draws the "unavailable" icon (monitor with a red cross) even
when traffic works.

The image fixes this in two parts:

1. **NetworkManager takes ownership of the uplink.** `webtop-nm-uplink.service`
   creates a `pod-uplink` profile (`type tun`, `mode tap`) for the interface
   carrying the default route and activates it at boot, using the address pasta
   already assigned. `NET_ADMIN` is required for that activation. With it,
   `nmcli` reports `eth0 tun connected pod-uplink`, `PrimaryConnection` is set,
   and `nmcli networking connectivity` is `full`.
2. **plasma-nm understands the uplink.** The image rebuilds the Fedora
   `plasma-nm` SRPM with
   [`build/plasma-nm/0001-plasma-nm-treat-tun-veth-as-wired.patch`](../build/plasma-nm/0001-plasma-nm-treat-tun-veth-as-wired.patch),
   which renders `Tun`/`Veth` devices with the wired icon and includes them in
   the popup.

The profile is activated explicitly because NM refuses to autoconnect over an
interface it only *assumed* (upstream `nm-policy.c` allows that for loopback
only). No DHCP is used: pasta's DHCP server does not reliably answer after NM
flushes the link, so the service reads the current address/gateway from the tap
and writes a static profile on every boot.

For a **pod** deployment, give the pasta interface a stable name and add the
capability to the container:

```ini
# webtop.pod
[Pod]
PodName=webtop
PublishPort=3000:3000
DNS=1.1.1.1
DNS=9.9.9.9
Network=pasta:--ns-ifname=eth0
```

```ini
# webtop.container
[Container]
AddCapability=NET_ADMIN
```

On a plain `podman run`, `--network pasta:--ns-ifname=eth0 --cap-add NET_ADMIN`
has the same effect. Without `NET_ADMIN` the service logs a warning, leaves the
container's original networking untouched, and the icon stays "unavailable".

Verify inside the container:

```bash
podman exec webtop nmcli device status          # eth0 tun connected pod-uplink
podman exec webtop nmcli networking connectivity # full
podman exec webtop curl -sI https://flathub.org
```

`ping` also needs `NET_RAW`, which is in Podman's default rootless capability
set. Explicit DNS (`DNS=1.1.1.1` on the pod) is still recommended when the host
resolver is not reachable from the container netns. The image sets
`dns=none`, so NM leaves the container's `/etc/resolv.conf` alone.

---

## 6. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `bwrap: Creating new namespace failed` | Missing `--cap-add SYS_ADMIN`. |
| `bwrap: Can't mount devpts … Permission denied` | Missing `--security-opt label=disable`. |
| `bwrap: Can't mount proc on /proc: Operation not permitted` | Missing `--security-opt seccomp=unconfined` or `--security-opt unmask=all`. |
| `bwrap: Creating new namespace failed: Operation not permitted` | Missing `--security-opt seccomp=unconfined`. |
| AppImage: `failed to open … fuse` | Missing `--device /dev/fuse`; the wrapper falls back to extract-and-run. |
| `webtop-gpu-report` shows `llvmpipe` | No usable render node (software VM, or `/dev/dri` not passed). |
| Network icon shows a red cross | Missing `NET_ADMIN`, or the uplink is not named `eth0` (`Network=pasta:--ns-ifname=eth0`). Check `podman exec webtop nmcli device status` and `journalctl -u webtop-nm-uplink`. |
| No `VAProfile…` lines | Host GPU does not expose VA-API (e.g. virtio-gpu without virgl). |
| Flatpak app missing from the menu | Install it, then log out/in of the session (KDE rebuilds the menu on `kbuildsycoca6`). |
