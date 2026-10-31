# Webtop network indicator evidence

Captured on 2026-10-31 against `localhost/webtop` built from this branch
(Bazzite stable-44, NetworkManager 1.56.1, plasma-nm 6.7.5, KDE Plasma 6.7.5).
Both runs used the same networking (`--network pasta:--ns-ifname=eth0` plus
`--cap-add NET_ADMIN`) and a managed `pod-uplink` connection on `eth0`.

| File | Image | Result |
| --- | --- | --- |
| `tray-before.png` | stock `plasma-nm-6.7.5-1.fc44` | `network-unavailable` (monitor with red cross) although `curl https://example.com` returns 200 |
| `tray-after.png` | `plasma-nm-6.7.5-1.fc44.webtop1` (this branch) | `network-wired-activated` |
| `popup-after.jpg` | same patched image | popup lists "Connected / pod-uplink" |

`tray-after.png` was captured from an image where the `pod-uplink` profile was
created only by the baked `webtop-nm-uplink.service` (no manual setup):

```
$ podman exec nmfinal-test nmcli device status
DEVICE  TYPE  STATE      CONNECTION
eth0    tun   connected  pod-uplink
lo      loopback  connected (externally)  lo

$ podman exec nmfinal-test nmcli networking connectivity
full

$ podman exec nmfinal-test nmcli -t -f GENERAL.STATE device show eth0
GENERAL.STATE:100 (connected)
```

Without `--cap-add NET_ADMIN` the service logs
`could not activate pod-uplink (missing NET_ADMIN?)`, exits successfully, and
the container keeps its original (external) networking: `curl` still returns
200, the icon stays unavailable. Verified in the same test run.
