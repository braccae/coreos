#!/usr/bin/env python3
import glob
import os
import re
import subprocess
import sys

print("==================== [1] SCANNING ALL .FC AND FILE_CONTEXTS ====================")
all_files = (
    glob.glob("/etc/selinux/**/file_contexts*", recursive=True) +
    glob.glob("/var/lib/selinux/**/file_contexts*", recursive=True) +
    glob.glob("/var/lib/selinux/**/*.fc", recursive=True) +
    glob.glob("/usr/share/selinux/**/*.fc", recursive=True)
)

failed = False
for f in all_files:
    if not os.path.isfile(f) or f.endswith(".bin") or f.endswith(".homedirs"):
        continue
    
    # Run sefcontext_compile directly
    if os.path.exists("/usr/sbin/sefcontext_compile"):
        res = subprocess.run(["/usr/sbin/sefcontext_compile", "-o", "/dev/null", f], capture_output=True, text=True)
        if res.returncode != 0:
            print(f"FAILED SEFCONTEXT_COMPILE on {f}:")
            print(res.stderr or res.stdout)
            failed = True
    
    # Test line by line
    with open(f, "r", errors="replace") as fh:
        for idx, line in enumerate(fh, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if not parts:
                continue
            pattern = parts[0]
            try:
                re.compile(pattern)
            except Exception as e:
                print(f"  [REGEX ERROR] {f}:{idx}: {line} -> Error: {e}")
                failed = True

if not failed:
    print("All scanned context files passed regex compilation!")
print("================================================================================")
