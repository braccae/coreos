# System-wide Justfile

The base AlmaLinux bootc image (`ghcr.io/braccae/alma`) ships a **system-wide
justfile** installed at `/justfile`, plus the `just` command runner itself. Any
user on the system can therefore invoke the base recipes from **any working
directory**, without a project justfile.

---

## 1. How it works

### 1.1 Installation path

| Source | Installed to | Mechanism |
| ------ | ------------ | --------- |
| `rootfs/common/justfile` | `/justfile` | Base [Containerfile](../Containerfile) line `COPY rootfs/common/ /` |
| `just` binary | `/usr/bin/just` | Base [Containerfile](../Containerfile) `dnf install` list |

`just` is already present in the base image's package list, so this feature adds
**no Containerfile change** — dropping `rootfs/common/justfile` into the
overlay is sufficient.

### 1.2 Why `/justfile` is "system-wide"

`just` resolves recipes by walking from the current working directory up through
its ancestors, stopping at the **first** justfile it finds. Because `/justfile`
is an ancestor of *every* path on the filesystem, the recipes in it are reachable
from anywhere:

```
/home/core/project/src  ->  /home/core/project  ->  /home/core  ->  /home  ->  /   (found)
```

### 1.3 Precedence

A justfile **closer** to the working directory always wins. A user's
`~/justfile` or a project's `./justfile` therefore overrides the base recipes.
This is intended: the base justfile provides fallbacks, not mandatory behaviour.

### 1.4 Scope discipline

Keep `/justfile` limited to **system-wide, base-image-level** recipes. Image-,
host- or task-specific recipes belong in the repository justfiles
(`./justfile`, `./build/justfile`) or the relevant rootfs overlay. This avoids
turning the base justfile into a dumping ground that leaks into every image.

---

## 2. Recipes

### `default` — list the base recipes

```bash
just          # or: just default
```

Running a bare `just` from a directory with no closer justfile prints the recipe
list. It is the safe, non-destructive default.

### `be USER` — become another user in a login shell

```bash
just be            # become root
just be ansible    # become the `ansible` service user
```

Equivalent to `sudo -iu USER`: it opens the target user's login shell and starts
in that user's home directory. It is implemented with `run0(1)`, the
systemd-native privilege-escalation tool already used throughout this image
(see `rootfs/common/usr/sbin/setup-podman-user`), so authorization flows through
polkit and every invocation is recorded in the journal.

The recipe body:

```just
be USER="root":
    #!/usr/bin/env bash
    set -euo pipefail
    exec run0 --user="{{ USER }}" -i
```

`USER` defaults to `root`, so a bare `just be` drops into a root login shell.

### `setup-nix` — enable Nix (dx image only)

```bash
just setup-nix
```

Nix is shipped **only in the `dx` image** and every Nix unit ships disabled —
`nix.mount` and `nix-daemon.socket` are never on automatically. This recipe is
the supported way to turn it on:

1. seeds `/var/lib/nix` from the deployment's `/nix` (so store paths added by a
   new image are merged before the bind mount hides them),
2. enables and starts `nix.mount`,
3. relabels `/nix` and `/var/lib/nix` using the SELinux module baked into the
   image,
4. enables and starts `nix-daemon.socket`, then verifies the socket and prints
   `nix --version`.

It is idempotent and re-execs itself through `run0` when not run as root. On
images that do not ship Nix it exits with an explanatory error instead of
failing obscurely. In rootless containers the bind mount needs
`--cap-add SYS_ADMIN` (and `--security-opt label=disable` on an SELinux-enforcing
host); the recipe reports that if `nix.mount` fails.

---

## 3. Verification

Verified locally against the base image (`localhost/alma:restic-d1`, which is
built from the base [Containerfile](../Containerfile)). The justfile was
bind-mounted to `/justfile` to reproduce the deployed path.

### 3.1 Discovery from arbitrary directories

```console
$ cd / && just --list
Available recipes:
    be USER="root" # Become another user in a login shell — the `just be USER` shortcut.
    default        # List the recipes available from this system-wide justfile.
    setup-nix      # Enable Nix (dx image only) and verify it.

$ mkdir -p /var/lib/foo/bar && cd /var/lib/foo/bar && just --list
Available recipes:
    be USER="root" # Become another user in a login shell — the `just be USER` shortcut.
    default        # List the recipes available from this system-wide justfile.
    setup-nix      # Enable Nix (dx image only) and verify it.
```

Discovery succeeds from `/` **and** from a deeply nested directory that has no
justfile of its own — the core "system-wide" acceptance criterion.

### 3.2 `be` argument plumbing

`run0` was stubbed to print its arguments:

```console
$ just be ansible
STUB-run0 args: --user=ansible -i

$ just be
STUB-run0 args: --user=root -i
```

Confirms the `USER` parameter (default and override) is passed verbatim to
`run0 --user=<USER> -i`.

### 3.3 Formatting

```console
$ just --unstable --justfile /justfile --fmt --check
FORMAT OK
```

The file is canonical per `just --fmt`.

---

## 4. Extending

Add a recipe to `rootfs/common/justfile` with a **single summary comment line**
immediately above it (that line is what `just --list` displays), then rebuild
the base image. If the recipe needs host-specific behaviour, it likely does not
belong here — see §1.4.
