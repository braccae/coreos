#!/bin/bash
# ==============================================================================
# install-hermes.sh — install the Hermes Agent CLI system-wide into the base image
# ==============================================================================
#
# Invoked from the `final` stage of ../Containerfile via
#   RUN bash /tmp/build_scripts/install-hermes.sh
#
# Why this shape (all verified empirically against the real base image, see
# commit 800f622):
#
#   * The upstream installer (https://hermes-agent.nousresearch.com/install.sh)
#     is interactive and per-user by default. We run it non-interactively as
#     root so the CLI lands in the *image*, not in a user's home.
#   * HERMES_INSTALL_DIR = where the git checkout + launchers live.
#   * HERMES_HOME        = where config, state and the committed dependency
#     environment live. Keeping it *equal to the install dir* means the sealed
#     dependency facts (/usr/local/lib/hermes-agent/installs/<key>/facts.json)
#     resolve for a bare `podman run ... hermes`, not just for a login shell.
#     The Containerfile bakes the same value as `ENV HERMES_HOME` so runtime
#     exec inherits it (this mirrors the upstream image's `ENV HERMES_HOME`).
#   * --skip-browser --skip-computer-use: this is a server/OS image, not a
#     browser host. The CLI, gateway and agent runtime remain fully functional.
#
# The published launcher hardcodes absolute paths under the install dir, so the
# system-wide publish is a *symlink*, not a copy.
#
set -euo pipefail

export HERMES_INSTALL_DIR=/usr/local/lib/hermes-agent
export HERMES_HOME=/usr/local/lib/hermes-agent

# In the Alma bootc base /root is a symlink to /var/roothome, which does not
# exist yet. The installer needs a writable HOME to stage its downloads, so
# create the real directory and point HOME at it for the duration of the build.
mkdir -p /var/roothome
export HOME=/var/roothome

echo "==> Installing Hermes Agent CLI into ${HERMES_INSTALL_DIR}"
curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --non-interactive --skip-browser --skip-computer-use

# --- Publish the CLI on the default PATH for every user ----------------------
# No shell rc edits: /usr/local/bin is already on the default PATH.
ln -sf "${HERMES_INSTALL_DIR}/.hermes/bin/hermes" /usr/local/bin/hermes

# The install tree is read/execute-only for non-root users. (Runtime state under
# HERMES_HOME is owned by root, matching the upstream "one owner" model; a
# non-root user needs its own install or write access to HERMES_HOME.)
chmod -R a+rX "${HERMES_INSTALL_DIR}"

# Best-effort SELinux relabel of the new tree. The targeted policy does not know
# these paths yet, so never fail the build on it.
restorecon -R "${HERMES_INSTALL_DIR}" /usr/local/bin/hermes 2>/dev/null || true

# Drop the staging HOME so it does not bloat the image layer.
rm -rf /var/roothome

# Prove the install works at build time (fails the build if the CLI is broken).
/usr/local/bin/hermes --version

echo "==> Hermes Agent CLI installed and published at /usr/local/bin/hermes"
