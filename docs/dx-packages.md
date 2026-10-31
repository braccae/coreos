# DX Image Package Manifest

Authoritative inventory of every RPM installed in the DX variant image (`localhost/dx`), the developer-workstation AlmaLinux bootc image defined by [dx.Containerfile](../dx.Containerfile).

**Verified against:** `localhost/dx:c1-verify` (built and lint-verified in C1) — `rpm -qa` output captured in `evidence/dx-c1-verify-rpmqa.txt`, **701 RPMs total**.

---

## How this image is composed

The DX image is a thin delta on top of the shared AlmaLinux base: it inherits the entire base OS and adds the container-runtime packages plus the **Nix** stack, which ships **only** in this image.

```
ghcr.io/braccae/alma:latest   (base image)
        │
        └── dx.Containerfile   (adds the nix stack + rootfs/dx/; enables podman.socket)
```

> **Nix is dx-only.** The base image no longer ships Nix. `dx.Containerfile` installs it, seeds `/var/lib/nix`, bakes the `build/selinux/nix` policy and copies the `rootfs/dx/` overlay. Every Nix unit ships **disabled**: an operator opts in with `just setup-nix`, which seeds the store, enables `nix.mount` and starts `nix-daemon.socket`.

> **Manifest status:** the RPM listing below was captured while the Nix stack still lived in the base image (701 RPMs, then identical to the base). It predates the dx-only move — re-capture `rpm -qa` from a freshly built `localhost/alma:dx` before quoting the counts.

---

## Explicitly requested in dx.Containerfile

These are the packages named directly in the `dnf install` line. The DX image's identity is defined by this short list:

| Package | Role in the DX image |
| --- | --- |
| `podman` | Rootless container engine (CLI, daemon-less, `podman.socket` API) |
| `podman-docker` | `docker` CLI shim so Docker-oriented tooling targets Podman |
| `podman-compose` | Compose-file orchestration on top of Podman |
| `fuse-overlayfs` | Rootless overlay storage driver for nested/rootless containers |
| `nix` | Nix package manager (dx-only; store persisted at `/var/lib/nix`; units opt-in via `just setup-nix`) |

`dx.Containerfile` additionally runs `systemctl enable podman.socket` so the Podman API socket is active at first boot. Nix units are deliberately left disabled until `just setup-nix` runs.

---

## Full manifest — notable categories

The 701 installed RPMs fall into the groups below (pre-move capture). Sizes are the count of distinct package names in each group; a name may appear in more than one group only where genuinely ambiguous. Packages shown here are **inherited from the base image** unless noted in the section above — the `nix*` packages are now provided by `dx.Containerfile` itself.

### Container runtime & Docker-CLI compatibility (26)

| Package | NEVRA in image |
| --- | --- |
| `aardvark-dns` | `aardvark-dns-1.17.1-1.el10_2.x86_64` |
| `catatonit` | `catatonit-0.2.1-1.el10.x86_64` |
| `conmon` | `conmon-2.2.1-2.el10.x86_64` |
| `container-selinux` | `container-selinux-2.248.0-1.el10_2.noarch` |
| `containers-common` | `containers-common-5.8-2.el10.noarch` |
| `containers-common-extra` | `containers-common-extra-5.8-2.el10.noarch` |
| `criu` | `criu-4.2-2.el10_2.alma.1.x86_64` |
| `criu-libs` | `criu-libs-4.2-2.el10_2.alma.1.x86_64` |
| `crun` | `crun-1.27-2.el10_2.x86_64` |
| `fuse` | `fuse-2.9.9-25.el10.x86_64` |
| `fuse-common` | `fuse-common-3.16.2-5.el10.x86_64` |
| `fuse-libs` | `fuse-libs-2.9.9-25.el10.x86_64` |
| `fuse-overlayfs` | `fuse-overlayfs-1.16-1.el10_1.x86_64` |
| `fuse3` | `fuse3-3.16.2-5.el10.x86_64` |
| `fuse3-libs` | `fuse3-libs-3.16.2-5.el10.x86_64` |
| `netavark` | `netavark-1.17.2-1.el10.x86_64` |
| `passt` | `passt-0^20251210.gd04c480-7.el10_2.x86_64` |
| `passt-selinux` | `passt-selinux-0^20251210.gd04c480-7.el10_2.noarch` |
| `podman` | `podman-5.8.2-9.el10_2.alma.1.x86_64` |
| `podman-compose` | `podman-compose-1.5.0-1.el10_1.noarch` |
| `podman-docker` | `podman-docker-5.8.2-9.el10_2.alma.1.noarch` |
| `podman-sequoia` | `podman-sequoia-0.4.0~pqc.3-1.el10_2.x86_64` |
| `shadow-utils` | `shadow-utils-4.15.0-11.el10.x86_64` |
| `shadow-utils-subid` | `shadow-utils-subid-4.15.0-11.el10.x86_64` |
| `skopeo` | `skopeo-1.22.2-5.el10_2.x86_64` |
| `toolbox` | `toolbox-0.3-2.el10_2.x86_64` |

### Nix package manager (7)

| Package | NEVRA in image |
| --- | --- |
| `nix` | `nix-2.31.5-3.el10_2.x86_64` |
| `nix-core` | `nix-core-2.31.5-3.el10_2.x86_64` |
| `nix-daemon` | `nix-daemon-2.31.5-3.el10_2.noarch` |
| `nix-filesystem` | `nix-filesystem-2.31.5-3.el10_2.noarch` |
| `nix-legacy` | `nix-legacy-2.31.5-3.el10_2.noarch` |
| `nix-libs` | `nix-libs-2.31.5-3.el10_2.x86_64` |
| `nix-system` | `nix-system-2.31.5-3.el10_2.noarch` |

### SELinux & mandatory access control (18)

| Package | NEVRA in image |
| --- | --- |
| `checkpolicy` | `checkpolicy-3.10-1.el10.x86_64` |
| `libselinux` | `libselinux-3.10-1.el10.x86_64` |
| `libselinux-utils` | `libselinux-utils-3.10-1.el10.x86_64` |
| `libsemanage` | `libsemanage-3.10-1.el10.x86_64` |
| `libsepol` | `libsepol-3.10-1.el10.x86_64` |
| `policycoreutils` | `policycoreutils-3.10-2.el10_2.x86_64` |
| `policycoreutils-python-utils` | `policycoreutils-python-utils-3.10-2.el10_2.noarch` |
| `policycoreutils-restorecond` | `policycoreutils-restorecond-3.10-2.el10_2.x86_64` |
| `python3-libselinux` | `python3-libselinux-3.10-1.el10.x86_64` |
| `python3-libsemanage` | `python3-libsemanage-3.10-1.el10.x86_64` |
| `python3-policycoreutils` | `python3-policycoreutils-3.10-2.el10_2.noarch` |
| `python3-setools` | `python3-setools-4.6.0-3.el10.x86_64` |
| `selinux-policy` | `selinux-policy-42.1.18-4.el10_2.4.noarch` |
| `selinux-policy-extra` | `selinux-policy-extra-42.1.18-4.el10_2.4.noarch` |
| `selinux-policy-targeted` | `selinux-policy-targeted-42.1.18-4.el10_2.4.noarch` |
| `selinux-policy-targeted-extra` | `selinux-policy-targeted-extra-42.1.18-4.el10_2.4.noarch` |
| `setroubleshoot-plugins` | `setroubleshoot-plugins-3.3.14-11.el10.noarch` |
| `setroubleshoot-server` | `setroubleshoot-server-3.3.35-4.el10.x86_64` |

### Audit & host intrusion detection (7)

| Package | NEVRA in image |
| --- | --- |
| `audit` | `audit-4.0.3-5.el10.x86_64` |
| `audit-libs` | `audit-libs-4.0.3-5.el10.x86_64` |
| `audit-rules` | `audit-rules-4.0.3-5.el10.x86_64` |
| `crowdsec` | `crowdsec-1.8.1-1.el9.x86_64` |
| `crowdsec-firewall-bouncer-nftables` | `crowdsec-firewall-bouncer-nftables-0.0.36-1.el9.x86_64` |
| `python3-audit` | `python3-audit-4.0.3-5.el10.x86_64` |
| `wazuh-agent` | `wazuh-agent-4.14.9-1.x86_64` |

### Disk encryption & TPM (19)

| Package | NEVRA in image |
| --- | --- |
| `clevis` | `clevis-21-9.el10.x86_64` |
| `clevis-dracut` | `clevis-dracut-21-9.el10.x86_64` |
| `clevis-luks` | `clevis-luks-21-9.el10.x86_64` |
| `clevis-pin-tpm2` | `clevis-pin-tpm2-0.5.3-9.el10.x86_64` |
| `clevis-systemd` | `clevis-systemd-21-9.el10.x86_64` |
| `cryptsetup` | `cryptsetup-2.8.1-2.el10.x86_64` |
| `cryptsetup-libs` | `cryptsetup-libs-2.8.1-2.el10.x86_64` |
| `ima-evm-utils` | `ima-evm-utils-1.6.2-4.el10.x86_64` |
| `keyutils` | `keyutils-1.6.3-5.el10.x86_64` |
| `keyutils-libs` | `keyutils-libs-1.6.3-5.el10.x86_64` |
| `libkcapi` | `libkcapi-1.5.1-1.el10_2.x86_64` |
| `libkcapi-hasher` | `libkcapi-hasher-1.5.1-1.el10_2.x86_64` |
| `libkcapi-hmaccalc` | `libkcapi-hmaccalc-1.5.1-1.el10_2.x86_64` |
| `libluksmeta` | `libluksmeta-10-1.el10.x86_64` |
| `luksmeta` | `luksmeta-10-1.el10.x86_64` |
| `tpm2-tools` | `tpm2-tools-5.7-5.el10.x86_64` |
| `tpm2-tss` | `tpm2-tss-4.1.3-6.el10.x86_64` |
| `tpm2-tss-fapi` | `tpm2-tss-fapi-4.1.3-6.el10.x86_64` |
| `volume_key-libs` | `volume_key-libs-0.3.12-26.el10.x86_64` |

### Cockpit web console (6)

| Package | NEVRA in image |
| --- | --- |
| `cockpit-bridge` | `cockpit-bridge-356.3-1.el10_2.noarch` |
| `cockpit-files` | `cockpit-files-36-1.el10.noarch` |
| `cockpit-ostree` | `cockpit-ostree-222-1.el10.noarch` |
| `cockpit-podman` | `cockpit-podman-121-1.el10.noarch` |
| `cockpit-storaged` | `cockpit-storaged-356.3-1.el10_2.noarch` |
| `cockpit-system` | `cockpit-system-356.3-1.el10_2.noarch` |

### Identity & authentication (SSSD/AD) (28)

| Package | NEVRA in image |
| --- | --- |
| `adcli` | `adcli-0.9.3.1-3.el10.x86_64` |
| `adcli-selinux` | `adcli-selinux-0.9.3.1-3.el10.noarch` |
| `authselect` | `authselect-1.5.2-1.el10.x86_64` |
| `authselect-libs` | `authselect-libs-1.5.2-1.el10.x86_64` |
| `cyrus-sasl-gssapi` | `cyrus-sasl-gssapi-2.1.28-30.el10_2.x86_64` |
| `cyrus-sasl-lib` | `cyrus-sasl-lib-2.1.28-30.el10_2.x86_64` |
| `gssproxy` | `gssproxy-0.9.2-10.el10.x86_64` |
| `krb5-libs` | `krb5-libs-1.21.3-10.el10_2.x86_64` |
| `libsss_certmap` | `libsss_certmap-2.12.0-3.el10_2.2.x86_64` |
| `libsss_idmap` | `libsss_idmap-2.12.0-3.el10_2.2.x86_64` |
| `libsss_nss_idmap` | `libsss_nss_idmap-2.12.0-3.el10_2.2.x86_64` |
| `libsss_sudo` | `libsss_sudo-2.12.0-3.el10_2.2.x86_64` |
| `libwbclient` | `libwbclient-4.23.5-111.el10_2.x86_64` |
| `openldap` | `openldap-2.6.10-1.el10.x86_64` |
| `pam` | `pam-1.6.1-9.el10_2.1.x86_64` |
| `pam-libs` | `pam-libs-1.6.1-9.el10_2.1.x86_64` |
| `realmd` | `realmd-0.17.1-13.el10_1.x86_64` |
| `sssd` | `sssd-2.12.0-3.el10_2.2.x86_64` |
| `sssd-ad` | `sssd-ad-2.12.0-3.el10_2.2.x86_64` |
| `sssd-client` | `sssd-client-2.12.0-3.el10_2.2.x86_64` |
| `sssd-common` | `sssd-common-2.12.0-3.el10_2.2.x86_64` |
| `sssd-common-pac` | `sssd-common-pac-2.12.0-3.el10_2.2.x86_64` |
| `sssd-ipa` | `sssd-ipa-2.12.0-3.el10_2.2.x86_64` |
| `sssd-krb5` | `sssd-krb5-2.12.0-3.el10_2.2.x86_64` |
| `sssd-krb5-common` | `sssd-krb5-common-2.12.0-3.el10_2.2.x86_64` |
| `sssd-ldap` | `sssd-ldap-2.12.0-3.el10_2.2.x86_64` |
| `sssd-nfs-idmap` | `sssd-nfs-idmap-2.12.0-3.el10_2.2.x86_64` |
| `sssd-proxy` | `sssd-proxy-2.12.0-3.el10_2.2.x86_64` |

### Filesystems, storage & volume management (59)

| Package | NEVRA in image |
| --- | --- |
| `btrfs-progs` | `btrfs-progs-6.12-3.el10_0.x86_64` |
| `device-mapper` | `device-mapper-1.02.210-2.el10.x86_64` |
| `device-mapper-event` | `device-mapper-event-1.02.210-2.el10.x86_64` |
| `device-mapper-event-libs` | `device-mapper-event-libs-1.02.210-2.el10.x86_64` |
| `device-mapper-libs` | `device-mapper-libs-1.02.210-2.el10.x86_64` |
| `device-mapper-multipath` | `device-mapper-multipath-0.9.9-18.el10.x86_64` |
| `device-mapper-multipath-libs` | `device-mapper-multipath-libs-0.9.9-18.el10.x86_64` |
| `device-mapper-persistent-data` | `device-mapper-persistent-data-1.3.0-1.el10.x86_64` |
| `dosfstools` | `dosfstools-4.2-12.el10.x86_64` |
| `e2fsprogs` | `e2fsprogs-1.47.1-5.el10.x86_64` |
| `e2fsprogs-libs` | `e2fsprogs-libs-1.47.1-5.el10.x86_64` |
| `erofs-utils` | `erofs-utils-1.8.10-1.el10.x86_64` |
| `exfatprogs` | `exfatprogs-1.2.8-1.el10.x86_64` |
| `hdparm` | `hdparm-9.65-6.el10.x86_64` |
| `iscsi-initiator-utils` | `iscsi-initiator-utils-6.2.1.11-1.git4b3e853.el10_2.2.x86_64` |
| `iscsi-initiator-utils-iscsiuio` | `iscsi-initiator-utils-iscsiuio-6.2.1.11-1.git4b3e853.el10_2.2.x86_64` |
| `kmod-zfs` | `kmod-zfs-6.12.0-211.65.1.el10_2.x86_64-2.4.4-1.el10.x86_64` |
| `kpartx` | `kpartx-0.9.9-18.el10.x86_64` |
| `libatasmart` | `libatasmart-0.19-30.el10.x86_64` |
| `libblockdev` | `libblockdev-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-crypto` | `libblockdev-crypto-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-fs` | `libblockdev-fs-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-loop` | `libblockdev-loop-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-lvm` | `libblockdev-lvm-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-mdraid` | `libblockdev-mdraid-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-nvme` | `libblockdev-nvme-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-part` | `libblockdev-part-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-smart` | `libblockdev-smart-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-swap` | `libblockdev-swap-3.4.0-2.el10.alma.1.x86_64` |
| `libblockdev-utils` | `libblockdev-utils-3.4.0-2.el10.alma.1.x86_64` |
| `libnfsidmap` | `libnfsidmap-2.8.3-5.el10_2.x86_64` |
| `libnvme` | `libnvme-1.16.1-3.el10_2.x86_64` |
| `libnvpair3` | `libnvpair3-2.4.4-1.el10.x86_64` |
| `libudisks2` | `libudisks2-2.11.0-2.el10_2.1.alma.2.x86_64` |
| `libuutil3` | `libuutil3-2.4.4-1.el10.x86_64` |
| `libzfs7` | `libzfs7-2.4.4-1.el10.x86_64` |
| `libzpool7` | `libzpool7-2.4.4-1.el10.x86_64` |
| `lsscsi` | `lsscsi-0.32-15.el10.x86_64` |
| `lvm2` | `lvm2-2.03.36-2.el10.x86_64` |
| `lvm2-libs` | `lvm2-libs-2.03.36-2.el10.x86_64` |
| `mdadm` | `mdadm-4.4-3.el10_2.2.x86_64` |
| `nfs-utils` | `nfs-utils-2.8.3-5.el10_2.x86_64` |
| `nvme-cli` | `nvme-cli-2.16-2.el10.x86_64` |
| `parted` | `parted-3.6-7.el10.x86_64` |
| `python3-pyzfs` | `python3-pyzfs-2.4.4-1.el10.noarch` |
| `quota` | `quota-4.09-10.el10.x86_64` |
| `quota-nls` | `quota-nls-4.09-10.el10.noarch` |
| `rpcbind` | `rpcbind-1.2.7-3.el10.x86_64` |
| `sg3_utils` | `sg3_utils-1.48-7.el10_2.1.x86_64` |
| `sg3_utils-libs` | `sg3_utils-libs-1.48-7.el10_2.1.x86_64` |
| `udisks2` | `udisks2-2.11.0-2.el10_2.1.alma.2.x86_64` |
| `udisks2-iscsi` | `udisks2-iscsi-2.11.0-2.el10_2.1.alma.2.x86_64` |
| `udisks2-lvm2` | `udisks2-lvm2-2.11.0-2.el10_2.1.alma.2.x86_64` |
| `util-linux` | `util-linux-2.40.2-18.el10.x86_64` |
| `util-linux-core` | `util-linux-core-2.40.2-18.el10.x86_64` |
| `xfsprogs` | `xfsprogs-6.16.0-1.el10.x86_64` |
| `zfs` | `zfs-2.4.4-1.el10.x86_64` |
| `zfs-dracut` | `zfs-dracut-2.4.4-1.el10.noarch` |
| `zfs-test` | `zfs-test-2.4.4-1.el10.x86_64` |

### Backup, sync & file sharing (14)

| Package | NEVRA in image |
| --- | --- |
| `borgbackup` | `borgbackup-1.4.5-1.el10_2.x86_64` |
| `cifs-utils` | `cifs-utils-7.7-1.el10_2.x86_64` |
| `libsmbclient` | `libsmbclient-4.23.5-111.el10_2.x86_64` |
| `rsync` | `rsync-3.5.0-3.el10_2.x86_64` |
| `samba` | `samba-4.23.5-111.el10_2.x86_64` |
| `samba-client` | `samba-client-4.23.5-111.el10_2.x86_64` |
| `samba-client-libs` | `samba-client-libs-4.23.5-111.el10_2.x86_64` |
| `samba-common` | `samba-common-4.23.5-111.el10_2.noarch` |
| `samba-common-libs` | `samba-common-libs-4.23.5-111.el10_2.x86_64` |
| `samba-common-tools` | `samba-common-tools-4.23.5-111.el10_2.x86_64` |
| `samba-dcerpc` | `samba-dcerpc-4.23.5-111.el10_2.x86_64` |
| `samba-ldb-ldap-modules` | `samba-ldb-ldap-modules-4.23.5-111.el10_2.x86_64` |
| `samba-libs` | `samba-libs-4.23.5-111.el10_2.x86_64` |
| `samba-usershares` | `samba-usershares-4.23.5-111.el10_2.noarch` |

### Networking & firewall (32)

| Package | NEVRA in image |
| --- | --- |
| `NetworkManager` | `NetworkManager-1.56.0-2.el10_2.x86_64` |
| `NetworkManager-cloud-setup` | `NetworkManager-cloud-setup-1.56.0-2.el10_2.x86_64` |
| `NetworkManager-libnm` | `NetworkManager-libnm-1.56.0-2.el10_2.x86_64` |
| `NetworkManager-tui` | `NetworkManager-tui-1.56.0-2.el10_2.x86_64` |
| `avahi-libs` | `avahi-libs-0.9~rc2-2.el10.x86_64` |
| `bind-libs` | `bind-libs-9.18.33-15.el10_2.12.x86_64` |
| `bind-license` | `bind-license-9.18.33-15.el10_2.12.noarch` |
| `bind-utils` | `bind-utils-9.18.33-15.el10_2.12.x86_64` |
| `chrony` | `chrony-4.8-2.el10.x86_64` |
| `ethtool` | `ethtool-6.15-2.el10.x86_64` |
| `firewalld` | `firewalld-2.4.3-4.el10_2.noarch` |
| `firewalld-filesystem` | `firewalld-filesystem-2.4.3-4.el10_2.noarch` |
| `hostname` | `hostname-3.23-14.el10.x86_64` |
| `iproute` | `iproute-6.17.0-2.el10.x86_64` |
| `iproute-tc` | `iproute-tc-6.17.0-2.el10.x86_64` |
| `ipset` | `ipset-7.22-13.el10_2.x86_64` |
| `ipset-libs` | `ipset-libs-7.22-13.el10_2.x86_64` |
| `iptables-libs` | `iptables-libs-1.8.11-16.el10_2.x86_64` |
| `iptables-nft` | `iptables-nft-1.8.11-16.el10_2.x86_64` |
| `iptables-nft-services` | `iptables-nft-services-1.8.11-16.el10_2.noarch` |
| `iputils` | `iputils-20240905-5.el10.x86_64` |
| `libmnl` | `libmnl-1.0.5-7.el10.x86_64` |
| `libndp` | `libndp-1.9-2.el10.x86_64` |
| `libnetfilter_conntrack` | `libnetfilter_conntrack-1.0.9-12.el10.x86_64` |
| `libnfnetlink` | `libnfnetlink-1.0.2-3.el10.x86_64` |
| `libnftnl` | `libnftnl-1.3.0-3.el10.x86_64` |
| `libtirpc` | `libtirpc-1.3.5-1.el10.x86_64` |
| `net-tools` | `net-tools-2.0-0.73.20160912git.el10.x86_64` |
| `nftables` | `nftables-1.1.5-6.el10_2.x86_64` |
| `python3-nftables` | `python3-nftables-1.1.5-6.el10_2.x86_64` |
| `socat` | `socat-1.7.4.4-8.el10.x86_64` |
| `tailscale` | `tailscale-1.104.1-1.x86_64` |

### Developer tooling & shells (29)

| Package | NEVRA in image |
| --- | --- |
| `bash` | `bash-5.2.26-6.el10.x86_64` |
| `bash-completion` | `bash-completion-2.11-16.el10.noarch` |
| `bc` | `bc-1.07.1-23.el10.x86_64` |
| `fzf` | `fzf-0.58.0-2.el10_0.x86_64` |
| `gawk` | `gawk-5.3.0-6.el10_2.1.x86_64` |
| `gawk-all-langpacks` | `gawk-all-langpacks-5.3.0-6.el10_2.1.x86_64` |
| `git` | `git-2.52.0-1.el10.x86_64` |
| `git-core` | `git-core-2.52.0-1.el10.x86_64` |
| `git-core-doc` | `git-core-doc-2.52.0-1.el10.noarch` |
| `jq` | `jq-1.7.1-11.el10_2.2.x86_64` |
| `just` | `just-1.46.0-1.el10_2.x86_64` |
| `ksh` | `ksh-1.0.10-9.el10.x86_64` |
| `less` | `less-661-3.el10.x86_64` |
| `nano` | `nano-8.1-3.el10.x86_64` |
| `nodejs` | `nodejs-22.23.2-3.el10_2.x86_64` |
| `nodejs-docs` | `nodejs-docs-22.23.2-3.el10_2.noarch` |
| `nodejs-full-i18n` | `nodejs-full-i18n-22.23.2-3.el10_2.x86_64` |
| `nodejs-libs` | `nodejs-libs-22.23.2-3.el10_2.x86_64` |
| `nodejs-npm` | `nodejs-npm-10.9.8-1.22.23.2.3.el10_2.x86_64` |
| `python3` | `python3-3.12.15-1.el10_2.x86_64` |
| `python3-libs` | `python3-libs-3.12.15-1.el10_2.x86_64` |
| `python3-pip` | `python3-pip-23.3.2-11.el10_2.noarch` |
| `python3-pip-wheel` | `python3-pip-wheel-23.3.2-11.el10_2.noarch` |
| `python3-setuptools` | `python3-setuptools-69.0.3-12.el10_0.noarch` |
| `tmux` | `tmux-3.3a-13.20230918gitb202a2f.el10.x86_64` |
| `vim-data` | `vim-data-9.1.083-9.el10_2.22.noarch` |
| `vim-minimal` | `vim-minimal-9.1.083-9.el10_2.22.x86_64` |
| `which` | `which-2.21-44.el10_0.x86_64` |
| `zsh` | `zsh-5.9-15.el10.x86_64` |

### Virtualization & guest integration (3)

| Package | NEVRA in image |
| --- | --- |
| `libnbd` | `libnbd-1.24.1-1.el10.x86_64` |
| `qemu-guest-agent` | `qemu-guest-agent-10.1.0-16.el10_2.5.alma.1.x86_64` |
| `virt-what` | `virt-what-1.27-3.el10.x86_64` |

### Bootloader & firmware (31)

| Package | NEVRA in image |
| --- | --- |
| `amd-gpu-firmware` | `amd-gpu-firmware-20260827-23.3.el10_2.noarch` |
| `amd-ucode-firmware` | `amd-ucode-firmware-20260827-23.3.el10_2.noarch` |
| `atheros-firmware` | `atheros-firmware-20260827-23.3.el10_2.noarch` |
| `brcmfmac-firmware` | `brcmfmac-firmware-20260827-23.3.el10_2.noarch` |
| `cirrus-audio-firmware` | `cirrus-audio-firmware-20260827-23.3.el10_2.noarch` |
| `efi-filesystem` | `efi-filesystem-6-6.el10.alma.1.noarch` |
| `efibootmgr` | `efibootmgr-18-8.el10.x86_64` |
| `efivar-libs` | `efivar-libs-39-3.el10.x86_64` |
| `flashrom` | `flashrom-1.3.0-8.el10.x86_64` |
| `fwupd` | `fwupd-2.0.19-4.1.el10_2.x86_64` |
| `fwupd-efi` | `fwupd-efi-1.8-1.el10_2.alma.1.x86_64` |
| `fwupd-plugin-flashrom` | `fwupd-plugin-flashrom-2.0.19-4.1.el10_2.x86_64` |
| `grub2-common` | `grub2-common-2.12-46.el10_2.alma.1.noarch` |
| `grub2-efi-x64` | `grub2-efi-x64-2.12-46.el10_2.alma.1.x86_64` |
| `grub2-pc` | `grub2-pc-2.12-46.el10_2.alma.1.x86_64` |
| `grub2-pc-modules` | `grub2-pc-modules-2.12-46.el10_2.alma.1.noarch` |
| `grub2-tools` | `grub2-tools-2.12-46.el10_2.alma.1.x86_64` |
| `grub2-tools-minimal` | `grub2-tools-minimal-2.12-46.el10_2.alma.1.x86_64` |
| `intel-audio-firmware` | `intel-audio-firmware-20260827-23.3.el10_2.noarch` |
| `intel-gpu-firmware` | `intel-gpu-firmware-20260827-23.3.el10_2.noarch` |
| `linux-firmware` | `linux-firmware-20260827-23.3.el10_2.noarch` |
| `linux-firmware-whence` | `linux-firmware-whence-20260827-23.3.el10_2.noarch` |
| `microcode_ctl` | `microcode_ctl-20260812-0.el10_2.noarch` |
| `mokutil` | `mokutil-0.7.2-4.el10.alma.1.x86_64` |
| `mt7xxx-firmware` | `mt7xxx-firmware-20260827-23.3.el10_2.noarch` |
| `nvidia-gpu-firmware` | `nvidia-gpu-firmware-20260827-23.3.el10_2.noarch` |
| `nxpwireless-firmware` | `nxpwireless-firmware-20260827-23.3.el10_2.noarch` |
| `os-prober` | `os-prober-1.81-9.el10.x86_64` |
| `realtek-firmware` | `realtek-firmware-20260827-23.3.el10_2.noarch` |
| `shim-x64` | `shim-x64-16.1-4.el10.alma.1.x86_64` |
| `tiwilink-firmware` | `tiwilink-firmware-20260827-23.3.el10_2.noarch` |

### Transactional OS layer (bootc / ostree) (11)

| Package | NEVRA in image |
| --- | --- |
| `bootc` | `bootc-1.16.4-2.el10_2.alma.1.x86_64` |
| `bootupd` | `bootupd-0.2.35-1.el10_2.x86_64` |
| `composefs` | `composefs-1.0.8-1.el10.x86_64` |
| `composefs-libs` | `composefs-libs-1.0.8-1.el10.x86_64` |
| `dracut` | `dracut-107-9.el10_2.x86_64` |
| `dracut-network` | `dracut-network-107-9.el10_2.x86_64` |
| `dracut-squash` | `dracut-squash-107-9.el10_2.x86_64` |
| `ostree` | `ostree-2025.7-1.el10.x86_64` |
| `ostree-libs` | `ostree-libs-2025.7-1.el10.x86_64` |
| `rpm-ostree` | `rpm-ostree-2026.3-2.el10_2.x86_64` |
| `rpm-ostree-libs` | `rpm-ostree-libs-2026.3-2.el10_2.x86_64` |

### System management, tuning & diagnostics (59)

| Package | NEVRA in image |
| --- | --- |
| `crypto-policies` | `crypto-policies-20260216-1.git0e54016.el10_2.2.alma.1.noarch` |
| `crypto-policies-scripts` | `crypto-policies-scripts-20260216-1.git0e54016.el10_2.2.alma.1.noarch` |
| `dnf` | `dnf-4.20.0-22.el10_2.alma.1.noarch` |
| `dnf-data` | `dnf-data-4.20.0-22.el10_2.alma.1.noarch` |
| `dnf-plugins-core` | `dnf-plugins-core-4.7.0-10.el10.noarch` |
| `irqbalance` | `irqbalance-1.9.4-6.el10.x86_64` |
| `kdump-utils` | `kdump-utils-1.0.58-15.el10.x86_64` |
| `kernel` | `kernel-6.12.0-211.65.1.el10_2.x86_64` |
| `kernel-core` | `kernel-core-6.12.0-211.65.1.el10_2.x86_64` |
| `kernel-modules` | `kernel-modules-6.12.0-211.65.1.el10_2.x86_64` |
| `kernel-modules-core` | `kernel-modules-core-6.12.0-211.65.1.el10_2.x86_64` |
| `kernel-modules-extra` | `kernel-modules-extra-6.12.0-211.65.1.el10_2.x86_64` |
| `kernel-tools` | `kernel-tools-6.12.0-211.65.1.el10_2.x86_64` |
| `kernel-tools-libs` | `kernel-tools-libs-6.12.0-211.65.1.el10_2.x86_64` |
| `kexec-tools` | `kexec-tools-2.0.32-3.el10.x86_64` |
| `kmod` | `kmod-31-13.el10.x86_64` |
| `kmod-libs` | `kmod-libs-31-13.el10.x86_64` |
| `libcomps` | `libcomps-0.1.21-3.el10.x86_64` |
| `libdnf` | `libdnf-0.73.1-15.el10_2.alma.1.x86_64` |
| `libmodulemd` | `libmodulemd-2.15.0-12.el10.x86_64` |
| `librepo` | `librepo-1.19.0-1.el10.x86_64` |
| `libsolv` | `libsolv-0.7.33-5.el10_2.alma.1.x86_64` |
| `lm_sensors-libs` | `lm_sensors-libs-3.6.0-20.el10.x86_64` |
| `logrotate` | `logrotate-3.22.0-5.el10.x86_64` |
| `lsof` | `lsof-4.98.0-7.el10.x86_64` |
| `makedumpfile` | `makedumpfile-1.7.8-1.el10.x86_64` |
| `man-db` | `man-db-2.12.0-10.el10.x86_64` |
| `memstrack` | `memstrack-0.2.5-6.el10.x86_64` |
| `pcp` | `pcp-7.0.3-5.el10_2.x86_64` |
| `pcp-conf` | `pcp-conf-7.0.3-5.el10_2.x86_64` |
| `pcp-libs` | `pcp-libs-7.0.3-5.el10_2.x86_64` |
| `pcp-selinux` | `pcp-selinux-7.0.3-5.el10_2.x86_64` |
| `procps-ng` | `procps-ng-4.0.4-11.el10.x86_64` |
| `psmisc` | `psmisc-23.6-8.el10.x86_64` |
| `python3-dnf` | `python3-dnf-4.20.0-22.el10_2.alma.1.noarch` |
| `python3-dnf-plugins-core` | `python3-dnf-plugins-core-4.7.0-10.el10.noarch` |
| `python3-hawkey` | `python3-hawkey-0.73.1-15.el10_2.alma.1.x86_64` |
| `python3-libcomps` | `python3-libcomps-0.1.21-3.el10.x86_64` |
| `python3-libdnf` | `python3-libdnf-0.73.1-15.el10_2.alma.1.x86_64` |
| `python3-pcp` | `python3-pcp-7.0.3-5.el10_2.x86_64` |
| `python3-perf` | `python3-perf-6.12.0-211.65.1.el10_2.x86_64` |
| `python3-rpm` | `python3-rpm-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm` | `rpm-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm-build-libs` | `rpm-build-libs-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm-libs` | `rpm-libs-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm-plugin-audit` | `rpm-plugin-audit-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm-plugin-selinux` | `rpm-plugin-selinux-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm-plugin-systemd-inhibit` | `rpm-plugin-systemd-inhibit-4.19.1.1-23.el10.alma.1.x86_64` |
| `rpm-sequoia` | `rpm-sequoia-1.10.2.1-1.el10_2.x86_64` |
| `rpm-sign-libs` | `rpm-sign-libs-4.19.1.1-23.el10.alma.1.x86_64` |
| `sos` | `sos-4.11.2-4.el10_2.noarch` |
| `stalld` | `stalld-1.26.3-1.el10.x86_64` |
| `sysstat` | `sysstat-12.7.6-4.el10.x86_64` |
| `systemd` | `systemd-257-23.el10_2.2.alma.1.x86_64` |
| `systemd-libs` | `systemd-libs-257-23.el10_2.2.alma.1.x86_64` |
| `systemd-pam` | `systemd-pam-257-23.el10_2.2.alma.1.x86_64` |
| `systemd-udev` | `systemd-udev-257-23.el10_2.2.alma.1.x86_64` |
| `tuned` | `tuned-2.27.0-2.el10_2.noarch` |
| `zram-generator` | `zram-generator-1.1.2-14.el10.x86_64` |

### Database & storage clients (6)

| Package | NEVRA in image |
| --- | --- |
| `duktape` | `duktape-2.7.0-10.el10.x86_64` |
| `libpq` | `libpq-16.14-1.el10_2.x86_64` |
| `lmdb-libs` | `lmdb-libs-0.9.32-4.el10.x86_64` |
| `python3-psycopg2` | `python3-psycopg2-2.9.9-6.el10.x86_64` |
| `sqlite` | `sqlite-3.46.1-6.el10_2.x86_64` |
| `sqlite-libs` | `sqlite-libs-3.46.1-6.el10_2.x86_64` |

### SSH & remote access (6)

| Package | NEVRA in image |
| --- | --- |
| `libssh` | `libssh-0.12.0-3.el10_2.x86_64` |
| `libssh-config` | `libssh-config-0.12.0-3.el10_2.noarch` |
| `libssh2` | `libssh2-1.11.1-9.el10_2.x86_64` |
| `openssh` | `openssh-9.9p1-28.el10_2.alma.1.x86_64` |
| `openssh-clients` | `openssh-clients-9.9p1-28.el10_2.alma.1.x86_64` |
| `openssh-server` | `openssh-server-9.9p1-28.el10_2.alma.1.x86_64` |

### Certificates, crypto & trust (29)

| Package | NEVRA in image |
| --- | --- |
| `ca-certificates` | `ca-certificates-2025.2.80_v9.0.305-102.el10_1.noarch` |
| `cracklib` | `cracklib-2.9.11-8.el10.x86_64` |
| `cracklib-dicts` | `cracklib-dicts-2.9.11-8.el10.x86_64` |
| `gnupg2` | `gnupg2-2.4.5-4.el10_1.x86_64` |
| `gnutls` | `gnutls-3.8.10-5.el10_2.x86_64` |
| `gpgme` | `gpgme-1.23.2-6.el10.alma.1.x86_64` |
| `jose` | `jose-14-102.el10.x86_64` |
| `libassuan` | `libassuan-2.5.6-6.el10.x86_64` |
| `libcbor` | `libcbor-0.11.0-3.el10.x86_64` |
| `libfido2` | `libfido2-1.14.0-7.el10.x86_64` |
| `libgcrypt` | `libgcrypt-1.11.0-7.el10_2.x86_64` |
| `libgpg-error` | `libgpg-error-1.50-2.el10.x86_64` |
| `libjose` | `libjose-14-102.el10.x86_64` |
| `libksba` | `libksba-1.6.7-2.el10.x86_64` |
| `libpwquality` | `libpwquality-1.4.5-12.el10.x86_64` |
| `libsodium` | `libsodium-1.0.22-1.el10_2.x86_64` |
| `libtasn1` | `libtasn1-4.20.0-5.el10_2.x86_64` |
| `npth` | `npth-1.6-21.el10.x86_64` |
| `nspr` | `nspr-4.39.0-5.el10_0.x86_64` |
| `nss` | `nss-3.124.0-5.el10_0.x86_64` |
| `nss-altfiles` | `nss-altfiles-2.23.0-6.el10.x86_64` |
| `nss-softokn` | `nss-softokn-3.124.0-5.el10_0.x86_64` |
| `nss-softokn-freebl` | `nss-softokn-freebl-3.124.0-5.el10_0.x86_64` |
| `nss-sysinit` | `nss-sysinit-3.124.0-5.el10_0.x86_64` |
| `nss-util` | `nss-util-3.124.0-5.el10_0.x86_64` |
| `p11-kit` | `p11-kit-0.26.4-1.el10_2.x86_64` |
| `p11-kit-server` | `p11-kit-server-0.26.4-1.el10_2.x86_64` |
| `p11-kit-trust` | `p11-kit-trust-0.26.4-1.el10_2.x86_64` |
| `sequoia-sq` | `sequoia-sq-1.4.0.1-2.el10_2.x86_64` |

---

## Appendix A — Complete RPM inventory (701)

Verbatim `rpm -qa` output from `localhost/dx:c1-verify`, sorted lexicographically.

```text
NetworkManager-1.56.0-2.el10_2.x86_64
NetworkManager-cloud-setup-1.56.0-2.el10_2.x86_64
NetworkManager-libnm-1.56.0-2.el10_2.x86_64
NetworkManager-tui-1.56.0-2.el10_2.x86_64
WALinuxAgent-udev-2.14.0.1-3.el10.noarch
aardvark-dns-1.17.1-1.el10_2.x86_64
acl-2.4.0-1.el10_2.x86_64
adcli-0.9.3.1-3.el10.x86_64
adcli-selinux-0.9.3.1-3.el10.noarch
almalinux-gpg-keys-10.2-21.el10.x86_64
almalinux-release-10.2-21.el10.x86_64
almalinux-repos-10.2-21.el10.x86_64
alternatives-1.30-2.el10.x86_64
amd-gpu-firmware-20260827-23.3.el10_2.noarch
amd-ucode-firmware-20260827-23.3.el10_2.noarch
atheros-firmware-20260827-23.3.el10_2.noarch
attr-2.6.0-1.el10_2.x86_64
audit-4.0.3-5.el10.x86_64
audit-libs-4.0.3-5.el10.x86_64
audit-rules-4.0.3-5.el10.x86_64
authselect-1.5.2-1.el10.x86_64
authselect-libs-1.5.2-1.el10.x86_64
avahi-libs-0.9~rc2-2.el10.x86_64
basesystem-11-22.el10.noarch
bash-5.2.26-6.el10.x86_64
bash-completion-2.11-16.el10.noarch
bc-1.07.1-23.el10.x86_64
bind-libs-9.18.33-15.el10_2.12.x86_64
bind-license-9.18.33-15.el10_2.12.noarch
bind-utils-9.18.33-15.el10_2.12.x86_64
blake3-1.8.2-1.el10_1.x86_64
bluez-5.85-1.el10.x86_64
boost-context-1.83.0-7.el10.x86_64
boost-iostreams-1.83.0-7.el10.x86_64
boost-url-1.83.0-7.el10.x86_64
bootc-1.16.4-2.el10_2.alma.1.x86_64
bootupd-0.2.35-1.el10_2.x86_64
borgbackup-1.4.5-1.el10_2.x86_64
brcmfmac-firmware-20260827-23.3.el10_2.noarch
btrfs-progs-6.12-3.el10_0.x86_64
bubblewrap-0.10.0-3.el10.x86_64
busybox-1.37.0-4.el10_2.x86_64
bzip2-1.0.8-25.el10.x86_64
bzip2-libs-1.0.8-25.el10.x86_64
c-ares-1.34.6-2.el10_2.x86_64
ca-certificates-2025.2.80_v9.0.305-102.el10_1.noarch
catatonit-0.2.1-1.el10.x86_64
checkpolicy-3.10-1.el10.x86_64
chrony-4.8-2.el10.x86_64
cifs-utils-7.7-1.el10_2.x86_64
cirrus-audio-firmware-20260827-23.3.el10_2.noarch
clevis-21-9.el10.x86_64
clevis-dracut-21-9.el10.x86_64
clevis-luks-21-9.el10.x86_64
clevis-pin-tpm2-0.5.3-9.el10.x86_64
clevis-systemd-21-9.el10.x86_64
cloud-utils-growpart-0.33-11.el10.noarch
cockpit-bridge-356.3-1.el10_2.noarch
cockpit-files-36-1.el10.noarch
cockpit-ostree-222-1.el10.noarch
cockpit-podman-121-1.el10.noarch
cockpit-storaged-356.3-1.el10_2.noarch
cockpit-system-356.3-1.el10_2.noarch
composefs-1.0.8-1.el10.x86_64
composefs-libs-1.0.8-1.el10.x86_64
conmon-2.2.1-2.el10.x86_64
console-login-helper-messages-0.21.3-10.el10.noarch
console-login-helper-messages-issuegen-0.21.3-10.el10.noarch
console-login-helper-messages-profile-0.21.3-10.el10.noarch
container-selinux-2.248.0-1.el10_2.noarch
containers-common-5.8-2.el10.noarch
containers-common-extra-5.8-2.el10.noarch
coreutils-9.5-8.el10_2.1.x86_64
coreutils-common-9.5-8.el10_2.1.x86_64
cpio-2.15-3.el10.x86_64
cracklib-2.9.11-8.el10.x86_64
cracklib-dicts-2.9.11-8.el10.x86_64
criu-4.2-2.el10_2.alma.1.x86_64
criu-libs-4.2-2.el10_2.alma.1.x86_64
crowdsec-1.8.1-1.el9.x86_64
crowdsec-firewall-bouncer-nftables-0.0.36-1.el9.x86_64
crun-1.27-2.el10_2.x86_64
crypto-policies-20260216-1.git0e54016.el10_2.2.alma.1.noarch
crypto-policies-scripts-20260216-1.git0e54016.el10_2.2.alma.1.noarch
cryptsetup-2.8.1-2.el10.x86_64
cryptsetup-libs-2.8.1-2.el10.x86_64
cups-filesystem-2.4.10-18.el10_2.noarch
cups-libs-2.4.10-18.el10_2.x86_64
curl-8.12.1-4.el10_2.7.x86_64
cyrus-sasl-gssapi-2.1.28-30.el10_2.x86_64
cyrus-sasl-lib-2.1.28-30.el10_2.x86_64
dbus-1.14.10-5.el10.x86_64
dbus-broker-36-5.el10_2.x86_64
dbus-common-1.14.10-5.el10.noarch
dbus-libs-1.14.10-5.el10.x86_64
device-mapper-1.02.210-2.el10.x86_64
device-mapper-event-1.02.210-2.el10.x86_64
device-mapper-event-libs-1.02.210-2.el10.x86_64
device-mapper-libs-1.02.210-2.el10.x86_64
device-mapper-multipath-0.9.9-18.el10.x86_64
device-mapper-multipath-libs-0.9.9-18.el10.x86_64
device-mapper-persistent-data-1.3.0-1.el10.x86_64
diffutils-3.10-8.el10.x86_64
dmidecode-3.6-5.el10.x86_64
dnf-4.20.0-22.el10_2.alma.1.noarch
dnf-data-4.20.0-22.el10_2.alma.1.noarch
dnf-plugins-core-4.7.0-10.el10.noarch
dosfstools-4.2-12.el10.x86_64
dracut-107-9.el10_2.x86_64
dracut-network-107-9.el10_2.x86_64
dracut-squash-107-9.el10_2.x86_64
duktape-2.7.0-10.el10.x86_64
e2fsprogs-1.47.1-5.el10.x86_64
e2fsprogs-libs-1.47.1-5.el10.x86_64
efi-filesystem-6-6.el10.alma.1.noarch
efibootmgr-18-8.el10.x86_64
efivar-libs-39-3.el10.x86_64
elfutils-debuginfod-client-0.194-2.el10_2.x86_64
elfutils-default-yama-scope-0.194-2.el10_2.noarch
elfutils-libelf-0.194-2.el10_2.x86_64
elfutils-libs-0.194-2.el10_2.x86_64
epel-release-10-8.el10_2.noarch
erofs-utils-1.8.10-1.el10.x86_64
ethtool-6.15-2.el10.x86_64
exfatprogs-1.2.8-1.el10.x86_64
expat-2.7.3-1.el10_2.5.x86_64
file-5.45-9.el10.x86_64
file-libs-5.45-9.el10.x86_64
filesystem-3.18-17.el10.x86_64
findutils-4.10.0-5.el10.x86_64
fio-3.36-5.el10.x86_64
fio-engine-http-3.36-5.el10.x86_64
fio-engine-libaio-3.36-5.el10.x86_64
fio-engine-nbd-3.36-5.el10.x86_64
fio-engine-rados-3.36-5.el10.x86_64
fio-engine-rbd-3.36-5.el10.x86_64
fio-engine-rdma-3.36-5.el10.x86_64
firewalld-2.4.3-4.el10_2.noarch
firewalld-filesystem-2.4.3-4.el10_2.noarch
flashrom-1.3.0-8.el10.x86_64
flatpak-session-helper-1.16.0-9.el10_2.4.x86_64
fstrm-0.6.1-12.el10.x86_64
fuse-2.9.9-25.el10.x86_64
fuse-common-3.16.2-5.el10.x86_64
fuse-libs-2.9.9-25.el10.x86_64
fuse-overlayfs-1.16-1.el10_1.x86_64
fuse3-3.16.2-5.el10.x86_64
fuse3-libs-3.16.2-5.el10.x86_64
fwupd-2.0.19-4.1.el10_2.x86_64
fwupd-efi-1.8-1.el10_2.alma.1.x86_64
fwupd-plugin-flashrom-2.0.19-4.1.el10_2.x86_64
fzf-0.58.0-2.el10_0.x86_64
gawk-5.3.0-6.el10_2.1.x86_64
gawk-all-langpacks-5.3.0-6.el10_2.1.x86_64
gc-8.2.6-4.el10_1.x86_64
gdbm-1.23-12.el10_0.x86_64
gdbm-libs-1.23-12.el10_0.x86_64
gettext-0.22.5-6.el10.x86_64
gettext-envsubst-0.22.5-6.el10.x86_64
gettext-libs-0.22.5-6.el10.x86_64
gettext-runtime-0.22.5-6.el10.x86_64
git-2.52.0-1.el10.x86_64
git-core-2.52.0-1.el10.x86_64
git-core-doc-2.52.0-1.el10.noarch
glib2-2.80.4-12.el10_2.22.x86_64
glibc-2.39-142.el10_2.alma.1.x86_64
glibc-common-2.39-142.el10_2.alma.1.x86_64
glibc-gconv-extra-2.39-142.el10_2.alma.1.x86_64
glibc-minimal-langpack-2.39-142.el10_2.alma.1.x86_64
gmp-6.2.1-12.el10.x86_64
gnupg2-2.4.5-4.el10_1.x86_64
gnutls-3.8.10-5.el10_2.x86_64
gobject-introspection-1.79.1-6.el10.x86_64
gpg-pubkey-145ce2f2-645ce3dc
gpg-pubkey-29111145-579ec98c
gpg-pubkey-3cdf0db4-605092b1
gpg-pubkey-6e93cd0c-60c07349
gpg-pubkey-957f5868-5e5499b8
gpg-pubkey-c2a1e572-668fe8ef
gpg-pubkey-e37ed158-65785fa9
gpgme-1.23.2-6.el10.alma.1.x86_64
grep-3.11-10.el10.x86_64
groff-base-1.23.0-10.el10.x86_64
grub2-common-2.12-46.el10_2.alma.1.noarch
grub2-efi-x64-2.12-46.el10_2.alma.1.x86_64
grub2-pc-2.12-46.el10_2.alma.1.x86_64
grub2-pc-modules-2.12-46.el10_2.alma.1.noarch
grub2-tools-2.12-46.el10_2.alma.1.x86_64
grub2-tools-minimal-2.12-46.el10_2.alma.1.x86_64
gssproxy-0.9.2-10.el10.x86_64
gzip-1.13-4.el10_2.x86_64
hdparm-9.65-6.el10.x86_64
hostname-3.23-14.el10.x86_64
hwdata-0.379-10.8.el10.noarch
ima-evm-utils-1.6.2-4.el10.x86_64
inih-58-3.el10.x86_64
initscripts-service-10.26-2.el10.noarch
intel-audio-firmware-20260827-23.3.el10_2.noarch
intel-gpu-firmware-20260827-23.3.el10_2.noarch
iproute-6.17.0-2.el10.x86_64
iproute-tc-6.17.0-2.el10.x86_64
ipset-7.22-13.el10_2.x86_64
ipset-libs-7.22-13.el10_2.x86_64
iptables-libs-1.8.11-16.el10_2.x86_64
iptables-nft-1.8.11-16.el10_2.x86_64
iptables-nft-services-1.8.11-16.el10_2.noarch
iputils-20240905-5.el10.x86_64
irqbalance-1.9.4-6.el10.x86_64
iscsi-initiator-utils-6.2.1.11-1.git4b3e853.el10_2.2.x86_64
iscsi-initiator-utils-iscsiuio-6.2.1.11-1.git4b3e853.el10_2.2.x86_64
isns-utils-libs-0.103-1.el10_2.1.x86_64
jansson-2.14-3.el10.x86_64
jose-14-102.el10.x86_64
jq-1.7.1-11.el10_2.2.x86_64
json-c-0.18-3.el10.x86_64
json-glib-1.8.0-5.el10.x86_64
just-1.46.0-1.el10_2.x86_64
kbd-2.6.4-8.el10_2.x86_64
kbd-legacy-2.6.4-8.el10_2.noarch
kbd-misc-2.6.4-8.el10_2.noarch
kdump-utils-1.0.58-15.el10.x86_64
kernel-6.12.0-211.65.1.el10_2.x86_64
kernel-core-6.12.0-211.65.1.el10_2.x86_64
kernel-modules-6.12.0-211.65.1.el10_2.x86_64
kernel-modules-core-6.12.0-211.65.1.el10_2.x86_64
kernel-modules-extra-6.12.0-211.65.1.el10_2.x86_64
kernel-tools-6.12.0-211.65.1.el10_2.x86_64
kernel-tools-libs-6.12.0-211.65.1.el10_2.x86_64
kexec-tools-2.0.32-3.el10.x86_64
keyutils-1.6.3-5.el10.x86_64
keyutils-libs-1.6.3-5.el10.x86_64
kmod-31-13.el10.x86_64
kmod-libs-31-13.el10.x86_64
kmod-zfs-6.12.0-211.65.1.el10_2.x86_64-2.4.4-1.el10.x86_64
kpartx-0.9.9-18.el10.x86_64
krb5-libs-1.21.3-10.el10_2.x86_64
ksh-1.0.10-9.el10.x86_64
less-661-3.el10.x86_64
libacl-2.4.0-1.el10_2.x86_64
libaio-0.3.111-22.el10.x86_64
libarchive-3.7.7-11.el10_2.x86_64
libassuan-2.5.6-6.el10.x86_64
libatasmart-0.19-30.el10.x86_64
libattr-2.6.0-1.el10_2.x86_64
libbabeltrace-1.5.11-9.el10.x86_64
libbasicobjects-0.1.1-58.el10.x86_64
libblkid-2.40.2-18.el10.x86_64
libblockdev-3.4.0-2.el10.alma.1.x86_64
libblockdev-crypto-3.4.0-2.el10.alma.1.x86_64
libblockdev-fs-3.4.0-2.el10.alma.1.x86_64
libblockdev-loop-3.4.0-2.el10.alma.1.x86_64
libblockdev-lvm-3.4.0-2.el10.alma.1.x86_64
libblockdev-mdraid-3.4.0-2.el10.alma.1.x86_64
libblockdev-nvme-3.4.0-2.el10.alma.1.x86_64
libblockdev-part-3.4.0-2.el10.alma.1.x86_64
libblockdev-smart-3.4.0-2.el10.alma.1.x86_64
libblockdev-swap-3.4.0-2.el10.alma.1.x86_64
libblockdev-utils-3.4.0-2.el10.alma.1.x86_64
libbpf-1.7.0-1.el10.x86_64
libbrotli-1.1.0-8.el10_2.x86_64
libbytesize-2.10-5.el10.x86_64
libcap-2.69-7.el10_2.1.x86_64
libcap-ng-0.8.4-6.el10.x86_64
libcap-ng-python3-0.8.4-6.el10.x86_64
libcbor-0.11.0-3.el10.x86_64
libcollection-0.7.0-58.el10.x86_64
libcom_err-1.47.1-5.el10.x86_64
libcomps-0.1.21-3.el10.x86_64
libcpuid-0.7.0-2.el10.x86_64
libcurl-8.12.1-4.el10_2.7.x86_64
libdhash-0.5.0-58.el10.x86_64
libdnf-0.73.1-15.el10_2.alma.1.x86_64
libdrm-2.4.128-1.el10.x86_64
libeconf-0.6.2-4.el10.x86_64
libedit-3.1-52.20230828cvs.el10.x86_64
libev-4.33-15.el10.x86_64
libevent-2.1.13-1.el10_2.x86_64
libfdisk-2.40.2-18.el10.x86_64
libffi-3.4.4-10.el10.x86_64
libfido2-1.14.0-7.el10.x86_64
libgcc-14.3.1-4.4.el10.alma.2.x86_64
libgcrypt-1.11.0-7.el10_2.x86_64
libgit2_1.9-1.9.7-1.el10_2.x86_64
libgomp-14.3.1-4.4.el10.alma.2.x86_64
libgpg-error-1.50-2.el10.x86_64
libgudev-238-7.el10.x86_64
libibverbs-61.0-1.el10.x86_64
libicu-74.2-5.el10_0.x86_64
libidn2-2.3.7-3.el10.x86_64
libini_config-1.3.1-58.el10.x86_64
libipa_hbac-2.12.0-3.el10_2.2.x86_64
libjcat-0.2.2-2.el10.x86_64
libjose-14-102.el10.x86_64
libkcapi-1.5.1-1.el10_2.x86_64
libkcapi-hasher-1.5.1-1.el10_2.x86_64
libkcapi-hmaccalc-1.5.1-1.el10_2.x86_64
libksba-1.6.7-2.el10.x86_64
libldb-4.23.5-111.el10_2.x86_64
libluksmeta-10-1.el10.x86_64
libmaxminddb-1.9.1-4.el10.x86_64
libmnl-1.0.5-7.el10.x86_64
libmodulemd-2.15.0-12.el10.x86_64
libmount-2.40.2-18.el10.x86_64
libnbd-1.24.1-1.el10.x86_64
libndp-1.9-2.el10.x86_64
libnet-1.3-7.el10.x86_64
libnetapi-4.23.5-111.el10_2.x86_64
libnetfilter_conntrack-1.0.9-12.el10.x86_64
libnfnetlink-1.0.2-3.el10.x86_64
libnfsidmap-2.8.3-5.el10_2.x86_64
libnftnl-1.3.0-3.el10.x86_64
libnghttp2-1.68.0-3.el10_2.2.x86_64
libnl3-3.11.0-1.el10.x86_64
libnvme-1.16.1-3.el10_2.x86_64
libnvpair3-2.4.4-1.el10.x86_64
libpath_utils-0.2.1-58.el10.x86_64
libpciaccess-0.16-16.el10.x86_64
libpipeline-1.5.7-7.el10.x86_64
libpkgconf-2.1.0-3.el10.x86_64
libpq-16.14-1.el10_2.x86_64
libpsl-0.21.5-6.el10.x86_64
libpwquality-1.4.5-12.el10.x86_64
librados2-18.2.1-4.el10.x86_64
librbd1-18.2.1-4.el10.x86_64
librdmacm-61.0-1.el10.x86_64
libref_array-0.1.5-58.el10.x86_64
librepo-1.19.0-1.el10.x86_64
libseccomp-2.5.6-1.el10.x86_64
libselinux-3.10-1.el10.x86_64
libselinux-utils-3.10-1.el10.x86_64
libsemanage-3.10-1.el10.x86_64
libsepol-3.10-1.el10.x86_64
libsmartcols-2.40.2-18.el10.x86_64
libsmbclient-4.23.5-111.el10_2.x86_64
libsodium-1.0.22-1.el10_2.x86_64
libsolv-0.7.33-5.el10_2.alma.1.x86_64
libss-1.47.1-5.el10.x86_64
libssh-0.12.0-3.el10_2.x86_64
libssh-config-0.12.0-3.el10_2.noarch
libssh2-1.11.1-9.el10_2.x86_64
libsss_certmap-2.12.0-3.el10_2.2.x86_64
libsss_idmap-2.12.0-3.el10_2.2.x86_64
libsss_nss_idmap-2.12.0-3.el10_2.2.x86_64
libsss_sudo-2.12.0-3.el10_2.2.x86_64
libstdc++-14.3.1-4.4.el10.alma.2.x86_64
libtalloc-2.4.3-100.el10.x86_64
libtasn1-4.20.0-5.el10_2.x86_64
libtdb-1.4.14-100.el10.x86_64
libtevent-0.17.1-100.el10.x86_64
libtirpc-1.3.5-1.el10.x86_64
libtraceevent-1.8.4-3.el10.x86_64
libudisks2-2.11.0-2.el10_2.1.alma.2.x86_64
libunistring-1.1-10.el10.x86_64
liburing-2.12-1.el10.x86_64
libusb1-1.0.30-1.el10_2.x86_64
libutempter-1.2.1-15.el10.x86_64
libuuid-2.40.2-18.el10.x86_64
libuutil3-2.4.4-1.el10.x86_64
libuv-1.52.1-1.el10_2.x86_64
libverto-0.3.2-10.el10.x86_64
libverto-libev-0.3.2-10.el10.x86_64
libwbclient-4.23.5-111.el10_2.x86_64
libxcrypt-4.4.36-10.el10.x86_64
libxkbcommon-1.7.0-4.el10.x86_64
libxml2-2.12.5-10.el10_2.4.x86_64
libxmlb-0.3.24-1.el10.x86_64
libyaml-0.2.5-16.el10.x86_64
libzfs7-2.4.4-1.el10.x86_64
libzpool7-2.4.4-1.el10.x86_64
libzstd-1.5.5-9.el10.x86_64
linux-firmware-20260827-23.3.el10_2.noarch
linux-firmware-whence-20260827-23.3.el10_2.noarch
llhttp-9.1.3-10.el10.x86_64
llvm-filesystem-21.1.8-1.el10.alma.1.x86_64
llvm-libs-21.1.8-1.el10.alma.1.x86_64
lm_sensors-libs-3.6.0-20.el10.x86_64
lmdb-libs-0.9.32-4.el10.x86_64
logrotate-3.22.0-5.el10.x86_64
lowdown-libs-1.0.2-5.el10_0.x86_64
lsof-4.98.0-7.el10.x86_64
lsscsi-0.32-15.el10.x86_64
lua-libs-5.4.6-7.el10.x86_64
luksmeta-10-1.el10.x86_64
lvm2-2.03.36-2.el10.x86_64
lvm2-libs-2.03.36-2.el10.x86_64
lz4-libs-1.9.4-8.el10.x86_64
lzo-2.10-14.el10.x86_64
makedumpfile-1.7.8-1.el10.x86_64
man-db-2.12.0-10.el10.x86_64
mdadm-4.4-3.el10_2.2.x86_64
memstrack-0.2.5-6.el10.x86_64
microcode_ctl-20260812-0.el10_2.noarch
mokutil-0.7.2-4.el10.alma.1.x86_64
mpdecimal-2.5.1-12.el10.x86_64
mpfr-4.2.1-8.el10.x86_64
mt7xxx-firmware-20260827-23.3.el10_2.noarch
nano-8.1-3.el10.x86_64
ncurses-6.4-15.20240127.el10_1.x86_64
ncurses-base-6.4-15.20240127.el10_1.noarch
ncurses-libs-6.4-15.20240127.el10_1.x86_64
net-tools-2.0-0.73.20160912git.el10.x86_64
netavark-1.17.2-1.el10.x86_64
newt-0.52.24-5.el10.x86_64
nfs-utils-2.8.3-5.el10_2.x86_64
nftables-1.1.5-6.el10_2.x86_64
nix-2.31.5-3.el10_2.x86_64
nix-core-2.31.5-3.el10_2.x86_64
nix-daemon-2.31.5-3.el10_2.noarch
nix-filesystem-2.31.5-3.el10_2.noarch
nix-legacy-2.31.5-3.el10_2.noarch
nix-libs-2.31.5-3.el10_2.x86_64
nix-system-2.31.5-3.el10_2.noarch
nodejs-22.23.2-3.el10_2.x86_64
nodejs-docs-22.23.2-3.el10_2.noarch
nodejs-full-i18n-22.23.2-3.el10_2.x86_64
nodejs-libs-22.23.2-3.el10_2.x86_64
nodejs-npm-10.9.8-1.22.23.2.3.el10_2.x86_64
npth-1.6-21.el10.x86_64
nspr-4.39.0-5.el10_0.x86_64
nss-3.124.0-5.el10_0.x86_64
nss-altfiles-2.23.0-6.el10.x86_64
nss-softokn-3.124.0-5.el10_0.x86_64
nss-softokn-freebl-3.124.0-5.el10_0.x86_64
nss-sysinit-3.124.0-5.el10_0.x86_64
nss-util-3.124.0-5.el10_0.x86_64
numactl-libs-2.0.19-3.el10.x86_64
nvidia-gpu-firmware-20260827-23.3.el10_2.noarch
nvme-cli-2.16-2.el10.x86_64
nxpwireless-firmware-20260827-23.3.el10_2.noarch
oniguruma-6.9.9-7.el10.x86_64
openldap-2.6.10-1.el10.x86_64
openssh-9.9p1-28.el10_2.alma.1.x86_64
openssh-clients-9.9p1-28.el10_2.alma.1.x86_64
openssh-server-9.9p1-28.el10_2.alma.1.x86_64
openssl-3.5.8-2.el10_2.alma.1.x86_64
openssl-fips-provider-3.5.8-2.el10_2.alma.1.x86_64
openssl-libs-3.5.8-2.el10_2.alma.1.x86_64
os-prober-1.81-9.el10.x86_64
ostree-2025.7-1.el10.x86_64
ostree-libs-2025.7-1.el10.x86_64
p11-kit-0.26.4-1.el10_2.x86_64
p11-kit-server-0.26.4-1.el10_2.x86_64
p11-kit-trust-0.26.4-1.el10_2.x86_64
pam-1.6.1-9.el10_2.1.x86_64
pam-libs-1.6.1-9.el10_2.1.x86_64
parted-3.6-7.el10.x86_64
passt-0^20251210.gd04c480-7.el10_2.x86_64
passt-selinux-0^20251210.gd04c480-7.el10_2.noarch
pciutils-libs-3.13.0-6.el10.x86_64
pcp-7.0.3-5.el10_2.x86_64
pcp-conf-7.0.3-5.el10_2.x86_64
pcp-libs-7.0.3-5.el10_2.x86_64
pcp-selinux-7.0.3-5.el10_2.x86_64
pcre2-10.44-1.5.el10_2.x86_64
pcre2-syntax-10.44-1.5.el10_2.noarch
perl-AutoLoader-5.74-515.el10_2.noarch
perl-B-1.89-515.el10_2.x86_64
perl-Carp-1.54-511.el10.noarch
perl-Class-Struct-0.68-515.el10_2.noarch
perl-Data-Dumper-2.189-512.el10.x86_64
perl-Digest-1.20-511.el10.noarch
perl-Digest-MD5-2.59-6.el10.x86_64
perl-DynaLoader-1.56-515.el10_2.x86_64
perl-Encode-3.21-511.el10.x86_64
perl-Errno-1.38-515.el10_2.x86_64
perl-Error-0.17029-18.el10.noarch
perl-Exporter-5.78-511.el10.noarch
perl-Fcntl-1.18-515.el10_2.x86_64
perl-File-Basename-2.86-515.el10_2.noarch
perl-File-Path-2.18-512.el10.noarch
perl-File-Temp-0.231.100-512.el10.noarch
perl-File-stat-1.14-515.el10_2.noarch
perl-FileHandle-2.05-515.el10_2.noarch
perl-Getopt-Long-2.58-3.el10.noarch
perl-Getopt-Std-1.14-515.el10_2.noarch
perl-Git-2.52.0-1.el10.noarch
perl-HTTP-Tiny-0.088-512.el10.noarch
perl-IO-1.55-515.el10_2.x86_64
perl-IO-Socket-IP-0.42-512.el10.noarch
perl-IO-Socket-SSL-2.085-3.el10.noarch
perl-IPC-Open3-1.22-515.el10_2.noarch
perl-MIME-Base64-3.16-511.el10.x86_64
perl-Mozilla-CA-20231213-5.el10.noarch
perl-NDBM_File-1.17-515.el10_2.x86_64
perl-Net-SSLeay-1.94-8.el10.x86_64
perl-POSIX-2.20-515.el10_2.x86_64
perl-PathTools-3.91-512.el10.x86_64
perl-Pod-Escapes-1.07-511.el10.noarch
perl-Pod-Perldoc-3.28.01-512.el10.noarch
perl-Pod-Simple-3.45-511.el10.noarch
perl-Pod-Usage-2.03-511.el10.noarch
perl-Scalar-List-Utils-1.63-511.el10.x86_64
perl-SelectSaver-1.02-515.el10_2.noarch
perl-Socket-2.038-511.el10.x86_64
perl-Storable-3.32-511.el10.x86_64
perl-Symbol-1.09-515.el10_2.noarch
perl-Term-ANSIColor-5.01-512.el10.noarch
perl-Term-Cap-1.18-511.el10.noarch
perl-TermReadKey-2.38-24.el10.x86_64
perl-Text-ParseWords-3.31-511.el10.noarch
perl-Text-Tabs+Wrap-2024.001-511.el10.noarch
perl-Time-Local-1.350-511.el10.noarch
perl-URI-5.27-3.el10.noarch
perl-base-2.27-515.el10_2.noarch
perl-constant-1.33-512.el10.noarch
perl-if-0.61.000-515.el10_2.noarch
perl-interpreter-5.40.2-515.el10_2.x86_64
perl-lib-0.65-515.el10_2.x86_64
perl-libnet-3.15-512.el10.noarch
perl-libs-5.40.2-515.el10_2.x86_64
perl-locale-1.12-515.el10_2.noarch
perl-mro-1.29-515.el10_2.x86_64
perl-overload-1.37-515.el10_2.noarch
perl-overloading-0.02-515.el10_2.noarch
perl-parent-0.241-512.el10.noarch
perl-podlators-5.01-511.el10.noarch
perl-vars-1.05-515.el10_2.noarch
pigz-2.8-7.el10.x86_64
pkgconf-2.1.0-3.el10.x86_64
pkgconf-m4-2.1.0-3.el10.noarch
pkgconf-pkg-config-2.1.0-3.el10.x86_64
podman-5.8.2-9.el10_2.alma.1.x86_64
podman-compose-1.5.0-1.el10_1.noarch
podman-docker-5.8.2-9.el10_2.alma.1.noarch
podman-sequoia-0.4.0~pqc.3-1.el10_2.x86_64
policycoreutils-3.10-2.el10_2.x86_64
policycoreutils-python-utils-3.10-2.el10_2.noarch
policycoreutils-restorecond-3.10-2.el10_2.x86_64
polkit-125-4.el10_2.1.x86_64
polkit-libs-125-4.el10_2.1.x86_64
polkit-pkla-compat-0.1-30.el10.x86_64
popt-1.19-8.el10.x86_64
procps-ng-4.0.4-11.el10.x86_64
protobuf-c-1.5.0-6.el10.x86_64
psmisc-23.6-8.el10.x86_64
publicsuffix-list-dafsa-20240107-5.el10.noarch
python-unversioned-command-3.12.15-1.el10_2.noarch
python3-3.12.15-1.el10_2.x86_64
python3-attrs-23.2.0-7.el10.noarch
python3-audit-4.0.3-5.el10.x86_64
python3-cffi-1.16.0-7.el10.x86_64
python3-charset-normalizer-3.4.2-1.el10.noarch
python3-click-8.1.7-7.el10_2.noarch
python3-dasbus-1.7-8.el10.noarch
python3-dateutil-2.9.0.post0-1.el10_0.noarch
python3-dbus-1.3.2-8.el10.x86_64
python3-distro-1.9.0-5.el10.noarch
python3-dnf-4.20.0-22.el10_2.alma.1.noarch
python3-dnf-plugins-core-4.7.0-10.el10.noarch
python3-dotenv+cli-1.0.1-3.el10_0.noarch
python3-dotenv-1.0.1-3.el10_0.noarch
python3-file-magic-5.45-9.el10.noarch
python3-firewall-2.4.3-4.el10_2.noarch
python3-gobject-base-3.46.0-7.el10.x86_64
python3-gobject-base-noarch-3.46.0-7.el10.noarch
python3-hawkey-0.73.1-15.el10_2.alma.1.x86_64
python3-idna-3.7-6.el10_2.noarch
python3-inotify-0.9.6-36.el10.noarch
python3-jsonschema-4.19.1-7.el10.noarch
python3-jsonschema-specifications-2023.11.2-6.el10.noarch
python3-libcomps-0.1.21-3.el10.x86_64
python3-libdnf-0.73.1-15.el10_2.alma.1.x86_64
python3-libs-3.12.15-1.el10_2.x86_64
python3-libselinux-3.10-1.el10.x86_64
python3-libsemanage-3.10-1.el10.x86_64
python3-libxml2-2.12.5-10.el10_2.4.x86_64
python3-linux-procfs-0.7.4-1.el10.noarch
python3-llfuse-1.5.1-1.el10_0.x86_64
python3-msgpack-1.1.1-1.el10_2.x86_64
python3-nftables-1.1.5-6.el10_2.x86_64
python3-packaging-24.2-2.el10.noarch
python3-pcp-7.0.3-5.el10_2.x86_64
python3-perf-6.12.0-211.65.1.el10_2.x86_64
python3-pexpect-4.9.0-6.el10.noarch
python3-pip-23.3.2-11.el10_2.noarch
python3-pip-wheel-23.3.2-11.el10_2.noarch
python3-ply-3.11-25.el10.noarch
python3-policycoreutils-3.10-2.el10_2.noarch
python3-psycopg2-2.9.9-6.el10.x86_64
python3-ptyprocess-0.7.0-9.el10.noarch
python3-pycparser-2.20-16.el10.noarch
python3-pyudev-0.24.1-10.el10.noarch
python3-pyyaml-6.0.1-19.el10.x86_64
python3-pyzfs-2.4.4-1.el10.noarch
python3-referencing-0.31.1-6.el10.noarch
python3-requests-2.32.4-1.el10_0.noarch
python3-rpds-py-0.17.1-6.el10.x86_64
python3-rpm-4.19.1.1-23.el10.alma.1.x86_64
python3-setools-4.6.0-3.el10.x86_64
python3-setuptools-69.0.3-12.el10_0.noarch
python3-six-1.16.0-16.el10.noarch
python3-systemd-235-11.el10.x86_64
python3-urllib3-1.26.19-4.el10_2.noarch
qemu-guest-agent-10.1.0-16.el10_2.5.alma.1.x86_64
quota-4.09-10.el10.x86_64
quota-nls-4.09-10.el10.noarch
readline-8.2-11.el10.x86_64
realmd-0.17.1-13.el10_1.x86_64
realtek-firmware-20260827-23.3.el10_2.noarch
rpcbind-1.2.7-3.el10.x86_64
rpm-4.19.1.1-23.el10.alma.1.x86_64
rpm-build-libs-4.19.1.1-23.el10.alma.1.x86_64
rpm-libs-4.19.1.1-23.el10.alma.1.x86_64
rpm-ostree-2026.3-2.el10_2.x86_64
rpm-ostree-libs-2026.3-2.el10_2.x86_64
rpm-plugin-audit-4.19.1.1-23.el10.alma.1.x86_64
rpm-plugin-selinux-4.19.1.1-23.el10.alma.1.x86_64
rpm-plugin-systemd-inhibit-4.19.1.1-23.el10.alma.1.x86_64
rpm-sequoia-1.10.2.1-1.el10_2.x86_64
rpm-sign-libs-4.19.1.1-23.el10.alma.1.x86_64
rpmfusion-free-release-10-1.noarch
rpmfusion-nonfree-release-10-1.noarch
rsync-3.5.0-3.el10_2.x86_64
samba-4.23.5-111.el10_2.x86_64
samba-client-4.23.5-111.el10_2.x86_64
samba-client-libs-4.23.5-111.el10_2.x86_64
samba-common-4.23.5-111.el10_2.noarch
samba-common-libs-4.23.5-111.el10_2.x86_64
samba-common-tools-4.23.5-111.el10_2.x86_64
samba-dcerpc-4.23.5-111.el10_2.x86_64
samba-ldb-ldap-modules-4.23.5-111.el10_2.x86_64
samba-libs-4.23.5-111.el10_2.x86_64
samba-usershares-4.23.5-111.el10_2.noarch
sed-4.9-5.el10.x86_64
selinux-policy-42.1.18-4.el10_2.4.noarch
selinux-policy-extra-42.1.18-4.el10_2.4.noarch
selinux-policy-targeted-42.1.18-4.el10_2.4.noarch
selinux-policy-targeted-extra-42.1.18-4.el10_2.4.noarch
sequoia-sq-1.4.0.1-2.el10_2.x86_64
setroubleshoot-plugins-3.3.14-11.el10.noarch
setroubleshoot-server-3.3.35-4.el10.x86_64
setup-2.14.5-7.el10.noarch
sg3_utils-1.48-7.el10_2.1.x86_64
sg3_utils-libs-1.48-7.el10_2.1.x86_64
shadow-utils-4.15.0-11.el10.x86_64
shadow-utils-subid-4.15.0-11.el10.x86_64
shared-mime-info-2.3-8.el10.x86_64
shim-x64-16.1-4.el10.alma.1.x86_64
skopeo-1.22.2-5.el10_2.x86_64
slang-2.3.3-8.el10.x86_64
snappy-1.1.10-7.el10.x86_64
socat-1.7.4.4-8.el10.x86_64
sos-4.11.2-4.el10_2.noarch
sqlite-3.46.1-6.el10_2.x86_64
sqlite-libs-3.46.1-6.el10_2.x86_64
sssd-2.12.0-3.el10_2.2.x86_64
sssd-ad-2.12.0-3.el10_2.2.x86_64
sssd-client-2.12.0-3.el10_2.2.x86_64
sssd-common-2.12.0-3.el10_2.2.x86_64
sssd-common-pac-2.12.0-3.el10_2.2.x86_64
sssd-ipa-2.12.0-3.el10_2.2.x86_64
sssd-krb5-2.12.0-3.el10_2.2.x86_64
sssd-krb5-common-2.12.0-3.el10_2.2.x86_64
sssd-ldap-2.12.0-3.el10_2.2.x86_64
sssd-nfs-idmap-2.12.0-3.el10_2.2.x86_64
sssd-proxy-2.12.0-3.el10_2.2.x86_64
stalld-1.26.3-1.el10.x86_64
sudo-1.9.17-10.p2.el10_2.7.x86_64
sudo-python-plugin-1.9.17-10.p2.el10_2.7.x86_64
sysstat-12.7.6-4.el10.x86_64
systemd-257-23.el10_2.2.alma.1.x86_64
systemd-libs-257-23.el10_2.2.alma.1.x86_64
systemd-pam-257-23.el10_2.2.alma.1.x86_64
systemd-udev-257-23.el10_2.2.alma.1.x86_64
tailscale-1.104.1-1.x86_64
tar-1.35-13.el10_2.x86_64
tbb-2021.11.0-7.el10.x86_64
tiwilink-firmware-20260827-23.3.el10_2.noarch
tmux-3.3a-13.20230918gitb202a2f.el10.x86_64
toolbox-0.3-2.el10_2.x86_64
tpm2-tools-5.7-5.el10.x86_64
tpm2-tss-4.1.3-6.el10.x86_64
tpm2-tss-fapi-4.1.3-6.el10.x86_64
tuned-2.27.0-2.el10_2.noarch
tzdata-2026e-1.el10_2.alma.1.noarch
udisks2-2.11.0-2.el10_2.1.alma.2.x86_64
udisks2-iscsi-2.11.0-2.el10_2.1.alma.2.x86_64
udisks2-lvm2-2.11.0-2.el10_2.1.alma.2.x86_64
unzip-6.0-69.el10.x86_64
userspace-rcu-0.14.0-7.el10.x86_64
util-linux-2.40.2-18.el10.x86_64
util-linux-core-2.40.2-18.el10.x86_64
vim-data-9.1.083-9.el10_2.22.noarch
vim-minimal-9.1.083-9.el10_2.22.x86_64
virt-what-1.27-3.el10.x86_64
volume_key-libs-0.3.12-26.el10.x86_64
wazuh-agent-4.14.9-1.x86_64
which-2.21-44.el10_0.x86_64
xdg-user-dirs-0.18-7.el10.x86_64
xfsprogs-6.16.0-1.el10.x86_64
xkeyboard-config-2.41-3.el10.noarch
xxhash-libs-0.8.4-1.el10_2.x86_64
xz-5.6.2-4.el10_2.1.x86_64
xz-libs-5.6.2-4.el10_2.1.x86_64
zfs-2.4.4-1.el10.x86_64
zfs-dracut-2.4.4-1.el10.noarch
zfs-test-2.4.4-1.el10.x86_64
zlib-ng-compat-2.2.3-3.el10_1.x86_64
zram-generator-1.1.2-14.el10.x86_64
zsh-5.9-15.el10.x86_64
zstd-1.5.5-9.el10.x86_64
```

## Appendix B — Transitive-only / base dependency set (307 names not in a notable category)

These are shared libraries, language runtimes, base-OS utilities, and dependency-only packages pulled in by the notable set above. They are not DX-specific; they exist to satisfy base-image and runtime dependencies.

```text
WALinuxAgent-udev
acl
almalinux-gpg-keys
almalinux-release
almalinux-repos
alternatives
attr
basesystem
blake3
bluez
boost-context
boost-iostreams
boost-url
bubblewrap
busybox
bzip2
bzip2-libs
c-ares
cloud-utils-growpart
console-login-helper-messages
console-login-helper-messages-issuegen
console-login-helper-messages-profile
coreutils
coreutils-common
cpio
cups-filesystem
cups-libs
curl
dbus
dbus-broker
dbus-common
dbus-libs
diffutils
dmidecode
elfutils-debuginfod-client
elfutils-default-yama-scope
elfutils-libelf
elfutils-libs
epel-release
expat
file
file-libs
filesystem
findutils
fio
fio-engine-http
fio-engine-libaio
fio-engine-nbd
fio-engine-rados
fio-engine-rbd
fio-engine-rdma
flatpak-session-helper
fstrm
gc
gdbm
gdbm-libs
gettext
gettext-envsubst
gettext-libs
gettext-runtime
glib2
glibc
glibc-common
glibc-gconv-extra
glibc-minimal-langpack
gmp
gobject-introspection
gpg-pubkey
gpg-pubkey-c2a1e572-668fe8ef
gpg-pubkey-e37ed158-65785fa9
grep
groff-base
gzip
hwdata
inih
initscripts-service
isns-utils-libs
jansson
json-c
json-glib
kbd
kbd-legacy
kbd-misc
libacl
libaio
libarchive
libattr
libbabeltrace
libbasicobjects
libblkid
libbpf
libbrotli
libbytesize
libcap
libcap-ng
libcap-ng-python3
libcollection
libcom_err
libcpuid
libcurl
libdhash
libdrm
libeconf
libedit
libev
libevent
libfdisk
libffi
libgcc
libgit2_1.9
libgomp
libgudev
libibverbs
libicu
libidn2
libini_config
libipa_hbac
libjcat
libldb
libmaxminddb
libmount
libnet
libnetapi
libnghttp2
libnl3
libpath_utils
libpciaccess
libpipeline
libpkgconf
libpsl
librados2
librbd1
librdmacm
libref_array
libseccomp
libsmartcols
libss
libstdc++
libtalloc
libtdb
libtevent
libtraceevent
libunistring
liburing
libusb1
libutempter
libuuid
libuv
libverto
libverto-libev
libxcrypt
libxkbcommon
libxml2
libxmlb
libyaml
libzstd
llhttp
llvm-filesystem
llvm-libs
lowdown-libs
lua-libs
lz4-libs
lzo
mpdecimal
mpfr
ncurses
ncurses-base
ncurses-libs
newt
numactl-libs
oniguruma
openssl
openssl-fips-provider
openssl-libs
pciutils-libs
pcre2
pcre2-syntax
perl-AutoLoader
perl-B
perl-Carp
perl-Class-Struct
perl-Data-Dumper
perl-Digest
perl-Digest-MD5
perl-DynaLoader
perl-Encode
perl-Errno
perl-Error
perl-Exporter
perl-Fcntl
perl-File-Basename
perl-File-Path
perl-File-Temp
perl-File-stat
perl-FileHandle
perl-Getopt-Long
perl-Getopt-Std
perl-Git
perl-HTTP-Tiny
perl-IO
perl-IO-Socket-IP
perl-IO-Socket-SSL
perl-IPC-Open3
perl-MIME-Base64
perl-Mozilla-CA
perl-NDBM_File
perl-Net-SSLeay
perl-POSIX
perl-PathTools
perl-Pod-Escapes
perl-Pod-Perldoc
perl-Pod-Simple
perl-Pod-Usage
perl-Scalar-List-Utils
perl-SelectSaver
perl-Socket
perl-Storable
perl-Symbol
perl-Term-ANSIColor
perl-Term-Cap
perl-TermReadKey
perl-Text-ParseWords
perl-Text-Tabs+Wrap
perl-Time-Local
perl-URI
perl-base
perl-constant
perl-if
perl-interpreter
perl-lib
perl-libnet
perl-libs
perl-locale
perl-mro
perl-overload
perl-overloading
perl-parent
perl-podlators
perl-vars
pigz
pkgconf
pkgconf-m4
pkgconf-pkg-config
polkit
polkit-libs
polkit-pkla-compat
popt
protobuf-c
publicsuffix-list-dafsa
python-unversioned-command
python3-attrs
python3-cffi
python3-charset-normalizer
python3-click
python3-dasbus
python3-dateutil
python3-dbus
python3-distro
python3-dotenv
python3-dotenv+cli
python3-file-magic
python3-firewall
python3-gobject-base
python3-gobject-base-noarch
python3-idna
python3-inotify
python3-jsonschema
python3-jsonschema-specifications
python3-libxml2
python3-linux-procfs
python3-llfuse
python3-msgpack
python3-packaging
python3-pexpect
python3-ply
python3-ptyprocess
python3-pycparser
python3-pyudev
python3-pyyaml
python3-referencing
python3-requests
python3-rpds-py
python3-six
python3-systemd
python3-urllib3
readline
rpmfusion-free-release
rpmfusion-nonfree-release
sed
setup
shared-mime-info
slang
snappy
sudo
sudo-python-plugin
tar
tbb
tzdata
unzip
userspace-rcu
xdg-user-dirs
xkeyboard-config
xxhash-libs
xz
xz-libs
zlib-ng-compat
zstd
```

---

*Generated from `rpm -qa` against the C1-verified DX image. Regenerate after any change to [dx.Containerfile](../dx.Containerfile) or the base image.*
