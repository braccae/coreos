#!/usr/bin/env bash
# ==============================================================================
# compare-images.sh — Semantic + rootfs comparison between two OCI images
# ==============================================================================
#
# Compares an "old" image against a "new" image built from refactored
# Containerfiles to verify functional equivalence while surfacing intentional
# hygiene improvements (fewer layers, smaller size, cleaned /tmp and DNF cache).
#
# Usage:
#   build/scripts/compare-images.sh [OPTIONS] <old_image> <new_image>
#
# Options:
#   --strict-versions   Compare full RPM NEVRA instead of package names only
#   --no-rootfs-diff    Skip merged rootfs diff (podman image mount)
#   --keep-tmp          Keep comparison workdir for manual inspection
#   -h, --help          Show this help
#
set -euo pipefail

STRICT_VERSIONS=false
ROOTFS_DIFF=true
KEEP_TMP=false

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict-versions) STRICT_VERSIONS=true; shift ;;
        --no-rootfs-diff)  ROOTFS_DIFF=false; shift ;;
        --keep-tmp)        KEEP_TMP=true; shift ;;
        -h|--help)         usage ;;
        -*)                echo "ERROR: unknown option: $1" >&2; exit 2 ;;
        *)                 break ;;
    esac
done

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 [OPTIONS] <old_image> <new_image>" >&2
    exit 2
fi

OLD_IMG="$1"
NEW_IMG="$2"

for img in "$OLD_IMG" "$NEW_IMG"; do
    if ! podman image exists "$img"; then
        echo "ERROR: image not found in local podman storage: ${img}" >&2
        exit 1
    fi
done

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/compare-images.XXXXXX")"
cleanup() {
    if [[ "$KEEP_TMP" == "true" ]]; then
        echo "Kept comparison artifacts in: ${WORKDIR}"
    else
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

extract_facts() {
    local img="$1"
    local out="$2"
    mkdir -p "$out"

    # 1. Image metadata & stats
    podman inspect "$img" > "${out}/inspect.json"
    python3 - "${out}/inspect.json" "${out}" <<'PY'
import json, sys, os
data = json.load(open(sys.argv[1]))[0]
out = sys.argv[2]
cfg = data.get("Config") or {}
rootfs = data.get("RootFS") or {}
layers = rootfs.get("Layers") or []

stats = {
    "size_bytes": data.get("Size", 0),
    "size_mb": round(data.get("Size", 0) / (1024 * 1024), 1),
    "layer_count": len(layers),
}
with open(os.path.join(out, "stats.json"), "w") as f:
    json.dump(stats, f, indent=2, sort_keys=True)

# Runtime-critical config fields (WorkingDir tracked separately as info)
runtime_cfg = {
    "Entrypoint": cfg.get("Entrypoint") or [],
    "Cmd": cfg.get("Cmd") or [],
    "User": cfg.get("User") or "",
    "Env": sorted(cfg.get("Env") or []),
}
with open(os.path.join(out, "config.json"), "w") as f:
    json.dump(runtime_cfg, f, indent=2, sort_keys=True)

with open(os.path.join(out, "workdir.txt"), "w") as f:
    f.write((cfg.get("WorkingDir") or "") + "\n")

labels = cfg.get("Labels") or {}
with open(os.path.join(out, "labels.txt"), "w") as f:
    for k in sorted(labels):
        # Ignore volatile build/base timestamps if present
        if k in ("org.opencontainers.image.created", "org.opencontainers.image.revision", "org.opencontainers.image.version"):
            continue
        f.write(f"{k}={labels[k]}\n")
PY

    # 2. Container-side semantic inventory (single fast podman run)
    local rpm_fmt='%{NAME}\n'
    if [[ "$STRICT_VERSIONS" == "true" ]]; then
        rpm_fmt='%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n'
    fi

    podman run --rm -i --entrypoint "" "$img" bash -s -- "$rpm_fmt" > "${out}/raw-inventory.txt" <<'INNER'
set -euo pipefail
RPM_FMT="$1"

echo "===SECTION:RPMS==="
rpm -qa --qf "${RPM_FMT}" | LC_ALL=C sort

echo "===SECTION:SYSTEMD_DEFAULT==="
systemctl get-default 2>/dev/null || true

echo "===SECTION:SYSTEMD_ENABLED==="
systemctl list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | awk '{print $1}' | LC_ALL=C sort || true

echo "===SECTION:SELINUX_MODULES==="
if command -v semodule >/dev/null 2>&1; then
    semodule -l 2>/dev/null | LC_ALL=C sort || true
fi

echo "===SECTION:USERS==="
LC_ALL=C sort /etc/passwd

echo "===SECTION:GROUPS==="
LC_ALL=C sort /etc/group

echo "===SECTION:SUDOERS==="
if [[ -d /etc/sudoers.d ]]; then
    find /etc/sudoers.d -maxdepth 2 -type f -printf '%m %p\n' | LC_ALL=C sort
fi

echo "===SECTION:REPOS==="
if [[ -d /etc/yum.repos.d ]]; then
    ls -1 /etc/yum.repos.d | LC_ALL=C sort
fi

echo "===SECTION:TMP==="
find /tmp -mindepth 1 -maxdepth 3 2>/dev/null | LC_ALL=C sort || true

echo "===SECTION:USR_LOCAL_BINS==="
if [[ -d /usr/local/bin ]]; then
    find /usr/local/bin -maxdepth 2 \( -type f -o -type l \) -printf '%m %p -> %l\n' | LC_ALL=C sort
fi

echo "===SECTION:COCKPIT==="
if [[ -d /usr/share/cockpit ]]; then
    ls -1 /usr/share/cockpit | LC_ALL=C sort
fi
INNER

    python3 - "${out}/raw-inventory.txt" "${out}" <<'PY'
import sys, os
src, out = sys.argv[1], sys.argv[2]
cur = None
buf = []
def flush():
    if cur is not None:
        with open(os.path.join(out, f"{cur.lower()}.txt"), "w") as f:
            f.writelines(buf)
with open(src) as f:
    for line in f:
        if line.startswith("===SECTION:") and line.strip().endswith("==="):
            flush()
            cur = line.strip()[len("===SECTION:"):-3]
            buf = []
        else:
            buf.append(line)
flush()
PY
}

echo "=============================================================================="
echo "Comparing images:"
echo "  OLD: ${OLD_IMG}"
echo "  NEW: ${NEW_IMG}"
echo "=============================================================================="

extract_facts "$OLD_IMG" "${WORKDIR}/old"
extract_facts "$NEW_IMG" "${WORKDIR}/new"

# --- Print stats comparison ---------------------------------------------------
python3 - "${WORKDIR}/old/stats.json" "${WORKDIR}/new/stats.json" <<'PY'
import json, sys
old = json.load(open(sys.argv[1]))
new = json.load(open(sys.argv[2]))
dl = new["layer_count"] - old["layer_count"]
ds = round(new["size_mb"] - old["size_mb"], 1)
print(f"\n[Image Stats]")
print(f"  Layers : {old['layer_count']} -> {new['layer_count']} ({dl:+d})")
print(f"  Size   : {old['size_mb']} MB -> {new['size_mb']} MB ({ds:+.1f} MB)")
PY

CRITICAL_DIFFS=0
INFO_DIFFS=0

compare_file() {
    local label="$1"
    local filename="$2"
    local severity="$3" # critical | info
    local f_old="${WORKDIR}/old/${filename}"
    local f_new="${WORKDIR}/new/${filename}"

    if diff -u --label "old/${filename}" --label "new/${filename}" "$f_old" "$f_new" > "${WORKDIR}/diff_${filename}"; then
        printf "  [PASS] %-28s identical\n" "$label"
    else
        if [[ "$severity" == "critical" ]]; then
            printf "  [DIFF] %-28s DIFFERENCES FOUND\n" "$label"
            CRITICAL_DIFFS=$((CRITICAL_DIFFS + 1))
        else
            printf "  [INFO] %-28s changed (informational)\n" "$label"
            INFO_DIFFS=$((INFO_DIFFS + 1))
        fi
        sed 's/^/         /' "${WORKDIR}/diff_${filename}" | head -n 60
        local total_lines
        total_lines="$(wc -l < "${WORKDIR}/diff_${filename}")"
        if [[ "$total_lines" -gt 60 ]]; then
            echo "         ... (${total_lines} diff lines total; rerun with --keep-tmp to inspect all)"
        fi
    fi
}

echo ""
echo "[Semantic Checks — Critical]"
compare_file "Runtime Config (Entry/Env)" "config.json" "critical"
compare_file "Installed RPMs"             "rpms.txt" "critical"
compare_file "Systemd Default Target"     "systemd_default.txt" "critical"
compare_file "Systemd Enabled Units"      "systemd_enabled.txt" "critical"
compare_file "SELinux Modules"            "selinux_modules.txt" "critical"
compare_file "Users (/etc/passwd)"        "users.txt" "critical"
compare_file "Groups (/etc/group)"        "groups.txt" "critical"
compare_file "Sudoers (/etc/sudoers.d)"   "sudoers.txt" "critical"
compare_file "Cockpit Modules"            "cockpit.txt" "critical"
compare_file "/usr/local/bin"             "usr_local_bins.txt" "critical"

echo ""
echo "[Hygiene & Metadata — Informational]"
compare_file "WorkingDir"                 "workdir.txt" "info"
compare_file "Labels"                     "labels.txt" "info"
compare_file "Yum Repos (/etc/yum.repos.d)" "repos.txt" "info"
compare_file "Leftover /tmp Contents"     "tmp.txt" "info"

# --- Optional merged rootfs diff ----------------------------------------------
if [[ "$ROOTFS_DIFF" == "true" ]]; then
    echo ""
    echo "[Merged Rootfs Diff (excluding caches, rpmdb, logs, tmp, initramfs, factory/etc)]"
    podman unshare bash -s -- "$OLD_IMG" "$NEW_IMG" "${WORKDIR}/rootfs.diff" <<'MOUNTDIFF' || true
set -euo pipefail
OLD_IMG="$1"
NEW_IMG="$2"
OUT_DIFF="$3"

OLD_MNT="$(podman image mount "$OLD_IMG")"
NEW_MNT="$(podman image mount "$NEW_IMG")"
trap 'podman image unmount "$OLD_IMG" >/dev/null 2>&1 || true; podman image unmount "$NEW_IMG" >/dev/null 2>&1 || true' EXIT

# Compare key OS trees while skipping expected volatile/cache/metadata paths
python3 - "$OLD_MNT" "$NEW_MNT" "$OUT_DIFF" <<'PY'
import os, hashlib, sys

old_root, new_root, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

IGNORE_PREFIXES = (
    "tmp/",
    "run/",
    "proc/",
    "sys/",
    "dev/",
    "var/cache/",
    "var/log/",
    "var/lib/dnf/",
    "var/lib/rpm/",
    "var/lib/selinux/",
    "var/lib/systemd/catalog/",
    "var/tmp/",
    "usr/share/factory/etc/",
    "etc/selinux/targeted/policy/",
    "etc/selinux/targeted/active/",
    "etc/selinux/targeted/contexts/files/",
    "etc/ld.so.cache",
    "etc/machine-id",
    "etc/shadow-",
    "etc/passwd-",
    "etc/group-",
    "etc/gshadow-",
    "usr/lib/sysimage/rpm/",
    "usr/share/rpm/",
)

IGNORE_EXACT = {
    "tmp", "run", "proc", "sys", "dev",
    "var/cache", "var/log", "var/lib/dnf", "var/lib/rpm", "var/tmp",
    "usr/share/factory/etc", "etc/ld.so.cache", "etc/machine-id",
    "usr/lib/sysimage/rpm", "usr/share/rpm",
}

def ignored(rel):
    if rel in IGNORE_EXACT:
        return True
    for p in IGNORE_PREFIXES:
        if rel.startswith(p):
            return True
    if "initramfs" in os.path.basename(rel):
        return True
    if rel.endswith(".pyc") or "__pycache__" in rel.split("/"):
        return True
    return False

def walk_tree(root):
    entries = {}
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir == ".":
            rel_dir = ""
        # Prune ignored subdirs
        kept = []
        for d in dirnames:
            rel = f"{rel_dir}/{d}" if rel_dir else d
            if not ignored(rel):
                kept.append(d)
                full = os.path.join(dirpath, d)
                if os.path.islink(full):
                    entries[rel] = ("symlink", os.readlink(full))
        dirnames[:] = kept

        for fn in filenames:
            rel = f"{rel_dir}/{fn}" if rel_dir else fn
            if ignored(rel):
                continue
            full = os.path.join(dirpath, fn)
            try:
                if os.path.islink(full):
                    entries[rel] = ("symlink", os.readlink(full))
                elif os.path.isfile(full):
                    st = os.lstat(full)
                    h = hashlib.sha256()
                    with open(full, "rb") as f:
                        for chunk in iter(lambda: f.read(65536), b""):
                            h.update(chunk)
                    entries[rel] = ("file", oct(st.st_mode & 0o7777), h.hexdigest())
            except OSError as e:
                entries[rel] = ("err", str(e))
    return entries

old_e = walk_tree(old_root)
new_e = walk_tree(new_root)

only_old = sorted(set(old_e) - set(new_e))
only_new = sorted(set(new_e) - set(old_e))
changed = sorted(k for k in (set(old_e) & set(new_e)) if old_e[k] != new_e[k])

with open(out_path, "w") as out:
    for k in only_old:
        out.write(f"- ONLY IN OLD: /{k}\n")
    for k in only_new:
        out.write(f"+ ONLY IN NEW: /{k}\n")
    for k in changed:
        out.write(f"~ CHANGED    : /{k}  (old={old_e[k][:2]} new={new_e[k][:2]})\n")

print(f"  Only in OLD : {len(only_old)}")
print(f"  Only in NEW : {len(only_new)}")
print(f"  Changed     : {len(changed)}")
PY
MOUNTDIFF

    if [[ -s "${WORKDIR}/rootfs.diff" ]]; then
        head -n 40 "${WORKDIR}/rootfs.diff" | sed 's/^/  /'
        total_fs="$(wc -l < "${WORKDIR}/rootfs.diff")"
        if [[ "$total_fs" -gt 40 ]]; then
            echo "  ... (${total_fs} total rootfs diff entries; rerun with --keep-tmp to inspect all)"
        fi
    else
        echo "  [PASS] Merged rootfs is 100% identical!"
    fi
fi

echo ""
echo "=============================================================================="
if [[ "$CRITICAL_DIFFS" -eq 0 ]]; then
    echo "RESULT: PASS (0 critical semantic differences, ${INFO_DIFFS} informational changes)"
    exit 0
else
    echo "RESULT: DIFF (${CRITICAL_DIFFS} critical semantic section(s) differ, ${INFO_DIFFS} informational changes)"
    exit 1
fi
