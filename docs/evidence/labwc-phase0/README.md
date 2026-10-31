# exp/labwc-phase0 — Selkies + patched labwc as nested session compositor

Goal: test whether a Selkies second display (`ADD_SCREEN`) shows usable KDE
content when the Selkies-patched labwc is the nested session compositor and
KWin runs nested inside it.

## Result (short)

`ADD_SCREEN` succeeds and a second capture output starts, but **screen 2 is an
empty labwc output (black), not KDE**. KWin's windowed Wayland backend renders
exactly one host window (`--output-count 1` by default) and does not create a
window for a parent output added later, so the screen labwc grows for
`display2` has no KDE content on it.

See `04-second-screen.png` (Selkies display 2) and `01-primary.png` (screen 1,
KDE). `insession-labwc-output1.png` is a grim capture taken from inside the
session on labwc's own socket.

## Versions

- labwc 0.9.7 (+ `labwc-ipc.patch`, `labwc-screens.patch`), built with
  `-Dxwayland=disabled`, `-Dnls=enabled`
- wlroots 0.19.3, built with `-Dxwayland=disabled`
- Source pinned to selkies-project/selkies commit
  `5dd987ce5de5ec5ed0c68e5c1f60168d0e0df30d` (`addons/base/build-labwc.sh`
  and `addons/base/patches/`), vendored under `build/labwc/`
- PREFIX `/usr/local` (Bazzite: `/usr/local -> ../var/usrlocal`)
- selkies 2.1.0 (PyPI venv), pixelflux Wayland capture
- KWin 6.7.5, Plasma on Bazzite stable-44

## Session wiring

```
pixelflux capture compositor  wayland-1   (Selkies)
  labwc (patched)             wayland-0   (+ $XDG_RUNTIME_DIR/labwc.sock)
    kwin_wayland              wayland-2   (--wayland-display wayland-0
                                           --socket wayland-2
                                           --no-lockscreen --xwayland)
      plasmashell / kded6 / kcminit / portals
SELKIES_APP_WAYLAND_DISPLAY=wayland-2
SELKIES_UI_SIDEBAR_SHOW_SCREEN_SETTINGS=true
```

labwc's own socket name comes from `wl_display_add_socket_auto()` with
`WAYLAND_DISPLAY=wayland-1` already taken, so it lands on `wayland-0`; the
launcher still detects it rather than assuming.

## Evidence of ADD_SCREEN

From `webtop.log`:

```
INFO:ws:Layout calculated: Total Size=2560x800. Layouts: {'primary': {... 'w': 1280}, 'display2': {'x': 1280, ... 'w': 1280}}
INFO:input:Session compositor added screen 'WL-2' for 'display2'.
INFO:ws:Capture started for 'display2': 1280x800 at +1280+0.
```

No `cannot add a screen`, `Could not find output`, or `session compositor
cannot add` lines appear in the log.

## Findings / regressions

1. **Screen 2 is empty.** `GET_WINDOWS` on labwc's IPC lists only the single
   KWin window (`WL-0`, 1280x800) on labwc's first output. New labwc outputs
   created by `ADD_SCREEN` receive no KWin window.
2. **labwc outputs accumulate.** `wlr-randr` on labwc's socket after a few
   display-2 reconnects/resizes shows `WL-1`..`WL-6`, laid out at x=0,1280,
   2560,...,6400. Selkies never sends `REMOVE_SCREEN` here: its screen
   bookkeeping uses `list_app_screens` on `SELKIES_APP_WAYLAND_DISPLAY`
   (KWin), which cannot see labwc's `WL-n` outputs, so each re-add grows a
   fresh labwc output.
3. **Resize works only with the maximize rule.** Without a labwc window rule,
   KWin's window stays 1024x768 and the capture shows black margins after a
   browser resize. `rc.xml` therefore maximises the undecorated
   `KDE Wayland Compositor*` window; resizes to 1024x700 and 1600x900 then
   fill correctly.
4. **Cost.** Both streams encode in software (no render node in this VM);
   with two 1280x800 streams the log shows `Backpressure TRIGGERED` for
   `display2`. The empty second screen still costs a full H.264 encode.

## Files

- `labwc.Containerfile` — experiment image (webtop + labwc builder stage)
- `build/labwc/` — vendored upstream build recipe and patches
- `rootfs/webtop/etc/xdg/labwc/rc.xml` — minimal nested config + maximize rule
- `rootfs/webtop/usr/local/bin/start-webtop.sh` — rewired session launcher

## Status: archived for a later retest

This branch is **not** a candidate to merge. It exists so the multi-screen
experiment can be rebuilt and retested after the separate streaming freeze is
fixed.

Two independent blockers:

1. **No usable second screen.** `ADD_SCREEN` succeeds and a capture starts, but
   KWin never creates a host toplevel for the output labwc adds, so screen 2 is
   black. See the result section above and `04-second-screen.png`.
2. **Session freeze.** Opening an application can freeze the whole stream
   (panel included) on the streamed session. The same freeze has been observed
   on the normal webtop image, so it predates this branch; it still has to be
   fixed before a multi-screen retest is meaningful. The GPU zero-copy path
   (`VAAPI`/`amdgpu`) was in use when it was last seen, and the second (empty)
   screen costs a full-size encode, so both are worth checking.

The built image from the original Phase 0 run was recovered after cleanup as a
dangling layer and tagged again:

- `localhost/webtop:labwc-exp`, image ID `49e545e102ba`
- labwc `0.9.7-dirty` built with `-Dxwayland=disabled`, wlroots 0.19.3
- it predates the NetworkManager/plasma-nm fix, so its tray icon shows a red
  cross even though networking works

Run it on a machine with a GPU render node:

```bash
podman run -d --name webtop-labwc \
  --systemd=always \
  --device /dev/dri --device /dev/fuse \
  --cap-add SYS_ADMIN --cap-add NET_ADMIN \
  --security-opt seccomp=unconfined --security-opt label=disable --security-opt unmask=all \
  --network 'pasta:--ns-ifname=eth0' --dns 1.1.1.1 \
  -p 127.0.0.1:3001:3000 \
  -v webtop-labwc-home:/home/webtop \
  -v webtop-labwc-flatpak:/var/lib/flatpak \
  localhost/webtop:labwc-exp
```

The dashboard requires a secure context, so reach it through a tunnel:

```bash
ssh -N -L 127.0.0.1:3001:127.0.0.1:3001 user@host
# browse http://127.0.0.1:3001
```

To rebuild from this branch:

```bash
podman build -f labwc.Containerfile -t localhost/webtop:labwc-exp .
```

The image is based on `main` at the time of the experiment; the branch itself
is based on current `main`, so a rebuild also includes the NetworkManager and
plasma-nm fixes merged later.
