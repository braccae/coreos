ARG installer_base=ghcr.io/braccae/coreos:workstation
FROM $installer_base

# --- Anaconda, dracut, grub2, and lorax packages for ISO installer builds ---
RUN --mount=type=bind,source=build/justfile,target=/tmp/build.justfile \
    just -f /tmp/build.justfile install-anaconda && \
    just -f /tmp/build.justfile cleanup-dnf