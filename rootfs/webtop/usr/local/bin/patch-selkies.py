import os

filepath = "/lsiopy/lib/python3.14/site-packages/selkies/selkies.py"
with open(filepath, "r") as f:
    content = f.read()

target = 'if display_state["encoder"] in ["jpeg", "x264enc-striped"]:'
replacement = 'if display_state["encoder"] in ["jpeg", "x264enc-striped"] or os.getenv("SELKIES_USE_CPU") in ["true", "1"]:'

if target in content:
    content = content.replace(target, replacement)
    with open(filepath, "w") as f:
        f.write(content)
    print("Successfully patched selkies.py")
else:
    print("Target string not found in selkies.py")
