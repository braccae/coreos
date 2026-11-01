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
  --device /dev/net/tun \
  --cap-add SYS_ADMIN \
  --cap-add NET_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --security-opt unmask=all \
  --shm-size 1g \
  --volume webtop-var:/var \
  --volume webtop-etc:/etc \
  -p 3000:3000 \
  ghcr.io/braccae/webtop:latest
```

| Flag | Why |
| --- | --- |
| `--device /dev/dri` | GPU render node for capture/encode (AMD, Intel, virtio-gpu/virgl). Omit for software rendering. |
| `--device /dev/fuse` | AppImage self-mounting. |
| `--device /dev/net/tun` | WireGuard clients (Tailscale, Cloudflare WARP) create `tun`/`wireguard` interfaces inside the container netns. `NET_ADMIN` is already required for NetworkManager; rootless pasta allows these interfaces. |
| `--cap-add SYS_ADMIN` | FUSE mounting (AppImages) needs it in the container's user namespace; `fusermount3` is setuid so the unprivileged session can use it. `--privileged` is **not** required. |
| `--cap-add NET_ADMIN` | Lets NetworkManager own the pasta tap instead of only *assuming* it, so the desktop network indicator reports a real connection. See [Network indicator](#network-indicator). |
| `--pids-limit=8192` | Headroom for the session's threads. Podman's default limit is 2048, and systemd caps `webtop.service` at 15% of that (307 tasks) unless the unit raises it. With the shipped unit the service is unbounded, but the container ceiling still applies. |
| `--shm-size=1g` | CEF/Chromium (Steam, Discover, Bazaar) needs more than the 64 MB default `/dev/shm`; otherwise `steamwebhelper` crash-loops. For pods, pass `--shm-size=1g` to `podman pod create`. |
| `--security-opt seccomp=unconfined` | `bwrap` must create user/PID namespaces (blocked by the default seccomp profile). |
| `--security-opt label=disable` | `bwrap` cannot mount `devpts`/`proc` under the container SELinux label. |
| `--security-opt unmask=all` | Podman's masked `/proc` paths prevent `bwrap` from mounting a fresh `/proc` inside its sandbox. |

The same settings are in the [`webtop.container`](../webtop.container) quadlet
(`AddDevice`, `AddCapability`, `SecurityLabelDisable`, volumes). That quadlet
uses socket activation instead of `-p 3000:3000`; see
[Socket activation](#socket-activation-native-rootless-ingress).

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

### Socket activation (native rootless ingress)

Rootless Podman forwards published ports through pasta, a userspace TCP stack.
A systemd socket avoids that path: `webtop.socket` binds the listener on the
host, Podman passes the fd into the container (`LISTEN_FDS=1`,
`LISTEN_PID=1`), and `/usr/local/bin/webtop-entrypoint` hands it to
`systemd-socket-proxyd` before exec'ing systemd. Traffic goes
host socket → kernel → proxy → Selkies, with no pasta hop.

```ini
# ~/.config/systemd/user/webtop.socket
[Unit]
Description=Webtop WebUI socket

[Socket]
ListenStream=127.0.0.1:3000
# For a host reverse proxy instead:
# ListenStream=%t/webtop-web.sock
# SocketMode=0600

[Install]
WantedBy=sockets.target
```

The container unit must reference the socket, use the entrypoint, and must
**not** publish 3000 or install itself:

```ini
# ~/.config/containers/systemd/webtop.container (changes only)
[Unit]
Requires=webtop.socket
After=webtop.socket

[Container]
Network=pasta:--ns-ifname=eth0,--address=192.0.2.2/24,--gateway=192.0.2.1
Entrypoint=/usr/local/bin/webtop-entrypoint
PodmanArgs=--pull=never --systemd=always --security-opt=unmask=all
# no PublishPort, no [Service] Restart=, no [Install]
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now webtop.socket
# first connect cold-boots the desktop (~30-60 s); the request is queued
curl --max-time 300 http://127.0.0.1:3000/
```

Keep `Restart=` off the container unit: when the desktop exits, the next
connection starts it again. `PodmanArgs=--pull=never` keeps the cold start from
checking the registry. If the browser gives up before the session reaches
`8082`, a refresh after boot is served normally.

For a Caddy/nginx edge, replace `ListenStream` with the Unix socket. The socket
file is created by the host's systemd, not by the container, so there is no
bind-mounted socket for SELinux to label; the container only inherits the fd.
Everything else in `webtop.container` (devices, caps, volumes) is unchanged.

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

### VPN clients (Tailscale, WARP)

Both clients are installed and can run at the same time (verified with both
`tailscale0` and `CloudflareWARP` up).

* Pass `--device /dev/net/tun` (the quadlet does). Rootless pasta owns the
  netns, so `NET_ADMIN` is enough to create the interfaces.
* Keep **IPv6 enabled**. WARP's Onoma DNS binds an IPv6 address; with
  `net.ipv6.conf.all.disable_ipv6=1` Connect aborts with
  `OnomaDnsServerError(SocketBind ... Cannot assign requested address)`.
* The image links `/usr/sbin/nft` and `/usr/sbin/tailscaled` because both
  clients hardcode the `/usr/sbin` paths while Fedora installs them in
  `/usr/bin`.
* Tailscale: enabled, starts as `tailscale0`; authenticate once with
  `tailscale up` (or `--authkey`).
* WARP: daemon enabled; register once with `warp-cli registration new` (or a
  token), then `warp-cli connect`. With a Teams registration the tunnel
  protocol is policy-controlled (MASQUE); WARP works once IPv6 is enabled.

A LAN-routable address still requires rootful macvlan; these give 100.x /
172.16.x overlay IPs.

### Persistence (bootc layout)

The image is built from a bootc base, so the root filesystem is read-only,
`/home` is a symlink to `/var/home`, and only `/var` and `/etc` are writable.
Persist exactly those two volumes:

* `/var` → home (`/var/home`), system Flatpak installs, the AppStream cache,
  WARP registration, container state and logs.
* `/etc` → configuration. `etc-overlay-sync.service` seeds `/etc` from
  `/usr/share/factory/etc` at boot and merges image updates into the persisted
  copy, while leaving runtime-owned files (`machine-id`, `hostname`,
  `resolv.conf`) alone.

Do not mount a separate `/home` volume: it shadows `/var/home` and breaks the
bootc layout.

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

The image already ships the drivers relevant to this:

* `radeonsi_dri.so` / `radeonsi_drv_video.so` (AMD OpenGL + VA-API)
* `iHD_drv_video.so` from `libva-intel-media-driver` (Intel Arc/Gen VA-API)
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
device, and `VAProfileH264…`/`VAProfileHEVC…` entries. On Intel Arc/Gen the
VA-API line reads `Driver version: Intel iHD driver …` instead. `llvmpipe` /
`virtio_gpu` means software rendering.

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

Give the pasta interface a stable name and add the capability to the container
(`webtop.container` is standalone; `webtop.socket` provides the ingress):

```ini
# webtop.container
[Container]
Network=pasta:--ns-ifname=eth0,--address=192.0.2.2/24,--gateway=192.0.2.1
AddCapability=NET_ADMIN
```

`--address`/`--gateway` give each container its own identity instead of
copying the host address into every namespace. `192.0.2.0/24` is RFC 5737
TEST-NET-1, reserved for documentation, so it cannot collide with a real LAN,
Podman's rootless/netavark bridges (`10.88.0.0/16`, `10.89.0.0/16`), WARP
(`172.16.0.0/12`, `10.64.0.0/24`) or Tailscale (`100.64.0.0/10`). Use `.2`,
`.3`, … per container with `.1` as the gateway. The address is local to the
container's network namespace: pasta still translates egress to the host
address, and nothing on the LAN can dial it — publish a port or use
`webtop.socket` for inbound access.

On a plain `podman run`,
`--network pasta:--ns-ifname=eth0,--address=192.0.2.2/24,--gateway=192.0.2.1 --cap-add NET_ADMIN`
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
| First `webtop.socket` connection hangs or resets | The desktop is cold-booting; the request is queued until Selkies binds `127.0.0.1:8082`. Wait for the boot and refresh. `systemctl --user status webtop.socket webtop.service`, and check `ss -ltn` shows the user systemd on port 3000 rather than pasta. |
| `webtop.service` starts at boot without the socket fd | The container unit still has `[Install]` or `Restart=always`. Remove both, `systemctl --user daemon-reload`, then let the socket start it on the first connection. |
| `bwrap: Creating new namespace failed` | Missing `--cap-add SYS_ADMIN`. |
| `bwrap: Can't mount devpts … Permission denied` | Missing `--security-opt label=disable`. |
| `bwrap: Can't mount proc on /proc: Operation not permitted` | Missing `--security-opt seccomp=unconfined` or `--security-opt unmask=all`. |
| `bwrap: Creating new namespace failed: Operation not permitted` | Missing `--security-opt seccomp=unconfined`. |
| AppImage: `failed to open … fuse` | Missing `--device /dev/fuse`; the wrapper falls back to extract-and-run. |
| `webtop-gpu-report` shows `llvmpipe` | No usable render node (software VM, or `/dev/dri` not passed). |
| Network icon shows a red cross | Missing `NET_ADMIN`, or the uplink is not named `eth0` (`Network=pasta:--ns-ifname=eth0`). Check `podman exec webtop nmcli device status` and `journalctl -u webtop-nm-uplink`. |
| Panel stops updating but windows still open/close | The session ran out of threads: `QThread::start: Thread creation error (Resource temporarily unavailable)` in the journal, and `systemctl show webtop -p TasksMax` low. The shipped unit sets `TasksMax=infinity`; the deployment must also raise the container limit (`PidsLimit=8192` or `--pids-limit=8192`). |
| `This session streams H.265 video, which this browser cannot decode` | The default encoder is H.264. If `SELKIES_ENCODER` is overridden to include `h265enc`, the client must support HEVC; remove it to restore H.264. |
| `cardwired.service` restart loop | Bazzite's Cardwire daemon needs eBPF/LSM and cannot run in the container (`CardwireEbpfError(LSMNotEnabled)`). The image disables it; re-enabling only restores the restart loop. |
| `ping: socket: Operation not permitted` | Fedora's `ping` has no file capabilities and the container's `ping_group_range` is `65534` only. The image sets `cap_net_raw+ep` on `/usr/bin/ping`; if a deployment strips capabilities (e.g. `--security-opt no-new-privileges`), restore it or use `sudo ping`/`curl` for reachability. |
| `sudo: pam_open_session: Permission denied` | Rootless user namespaces lack `CAP_SYS_RESOURCE`, so the stock `/etc/pam.d/sudo` `pam_limits.so` session line fails. The launcher removes that line at boot; `run0` also works. |
| `warp-cli status` → `Unable … Registration Missing` | The daemon is enabled by the image, but a WARP registration lives in `/var` and is per-deployment. Run `warp-cli registration new` (or `warp-cli registration token …`) once. |
| Steam exits at `surface_linux.cpp … glXChooseVisual failed` | The Steam runtime needs `/sbin/ldconfig`; Fedora 44 ships `/usr/bin/ldconfig` only. The image creates `/usr/sbin/ldconfig`; keep it when rebasing. |
| Bazaar shows empty catalog sections / "No Applications Found" | Flatpak AppStream metadata is missing or stale. The image runs `webtop-flatpak-appstream.service` at boot; force it with `flatpak update --appstream` and restart Bazaar. |
| Discover says "Application deployment is not enabled for this user" / install fails | The container has no logind session, so Fedora's Flatpak polkit rule (`subject.active && subject.local && wheel`) does not match. The image ships `49-webtop-flatpak.rules` and starts the agent from `/usr/libexec/kf6/`. Check with `pkcheck --action-id org.freedesktop.Flatpak.app-install --process $$`. |
| `org.freedesktop.secrets` missing / KWallet prompt | The session starts `kwalletd6` and `ksecretd` (the KDE Secret Service compatibility daemon). The first secret store may prompt once to create the `kdewallet` wallet; choose the classic (blowfish) option. |
| No `VAProfile…` lines | Host GPU does not expose VA-API (e.g. virtio-gpu without virgl). |
| Flatpak app missing from the menu | Install it, then log out/in of the session (KDE rebuilds the menu on `kbuildsycoca6`). |