#!/usr/bin/env python3
import glob
import os
import subprocess
import sys
import tempfile

print("==================== [1] LOCATING ACTIVE POLICY ====================")
policies = sorted(glob.glob("/etc/selinux/targeted/policy/policy.*"))
if not policies:
    print("ERROR: No policy found in /etc/selinux/targeted/policy/")
    sys.exit(1)

latest_policy = policies[-1]
print(f"Active Policy: {latest_policy}")

setfiles_bin = "/usr/sbin/setfiles"
if not os.path.exists(setfiles_bin):
    setfiles_bin = "/usr/bin/setfiles"

print(f"Using setfiles binary: {setfiles_bin}")
print("==================== [2] VALIDATING CONTEXT TYPES AGAINST POLICY ====================")

all_files = (
    glob.glob("/etc/selinux/**/file_contexts*", recursive=True) +
    glob.glob("/var/lib/selinux/**/file_contexts*", recursive=True) +
    glob.glob("/var/lib/selinux/**/*.fc", recursive=True) +
    glob.glob("/usr/share/selinux/**/*.fc", recursive=True)
)

failed_total = 0

for f in sorted(set(all_files)):
    if not os.path.isfile(f) or f.endswith(".bin") or f.endswith(".homedirs"):
        continue
    
    # Run setfiles -c <policy> <file>
    res = subprocess.run([setfiles_bin, "-c", latest_policy, "-v", f], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"\n[!] FAILED VALIDATION ON: {f}")
        print(res.stderr.strip() or res.stdout.strip())
        failed_total += 1
        
        # Test line-by-line to find every single offending rule in this file
        with open(f, "r", errors="replace") as fh:
            for idx, line in enumerate(fh, 1):
                clean_line = line.strip()
                if not clean_line or clean_line.startswith("#"):
                    continue
                
                with tempfile.NamedTemporaryFile("w", delete=False) as tf:
                    tf.write(line + "\n")
                    tf_name = tf.name
                
                line_res = subprocess.run([setfiles_bin, "-c", latest_policy, tf_name], capture_output=True, text=True)
                os.remove(tf_name)
                
                if line_res.returncode != 0:
                    err_msg = (line_res.stderr.strip() or line_res.stdout.strip()).replace(tf_name, f)
                    print(f"    -> Line {idx}: {clean_line}")
                    print(f"       Error: {err_msg}")

if failed_total == 0:
    print("All scanned context files are 100% valid against active policy!")
else:
    print(f"\n==================== TOTAL FAILING FILES: {failed_total} ====================")

print("================================================================================")
