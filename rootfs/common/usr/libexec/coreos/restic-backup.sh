#!/usr/bin/env bash
set -euo pipefail

# Preserve any non-empty environment overrides before sourcing /etc/restic/env
_override_RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
_override_RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"
_override_RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-}"
_override_RESTIC_OPTIONS="${RESTIC_OPTIONS:-}"
_override_BACKUP_PATHS="${BACKUP_PATHS:-}"

if [ -f /etc/restic/env ]; then
    set -a
    # shellcheck disable=SC1091
    . /etc/restic/env
    set +a
fi

[ -n "${_override_RESTIC_REPOSITORY}" ] && RESTIC_REPOSITORY="${_override_RESTIC_REPOSITORY}"
[ -n "${_override_RESTIC_PASSWORD}" ] && RESTIC_PASSWORD="${_override_RESTIC_PASSWORD}"
[ -n "${_override_RESTIC_PASSWORD_FILE}" ] && RESTIC_PASSWORD_FILE="${_override_RESTIC_PASSWORD_FILE}"
[ -n "${_override_RESTIC_OPTIONS}" ] && RESTIC_OPTIONS="${_override_RESTIC_OPTIONS}"
[ -n "${_override_BACKUP_PATHS}" ] && BACKUP_PATHS="${_override_BACKUP_PATHS}"

RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-}"
RESTIC_PASSWORD="${RESTIC_PASSWORD:-}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-}"
RESTIC_OPTIONS="${RESTIC_OPTIONS:-}"
BACKUP_PATHS="${BACKUP_PATHS:-/etc /var /home}"

if [ -z "${RESTIC_REPOSITORY}" ]; then
    err_msg="ERROR: RESTIC_REPOSITORY is empty or unset; failing closed."
    echo "restic-backup: ${err_msg}" >&2
    logger -t restic-backup "${err_msg}" 2>/dev/null || true
    exit 1
fi
export RESTIC_REPOSITORY
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/restic}"

# Resolve password: prefer RESTIC_PASSWORD, then systemd credential, then RESTIC_PASSWORD_FILE
if [ -z "${RESTIC_PASSWORD}" ]; then
    if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "${CREDENTIALS_DIRECTORY}/restic.pw" ]; then
        RESTIC_PASSWORD="$(cat "${CREDENTIALS_DIRECTORY}/restic.pw")"
        export RESTIC_PASSWORD
    elif [ -n "${RESTIC_PASSWORD_FILE}" ]; then
        export RESTIC_PASSWORD_FILE
    fi
else
    export RESTIC_PASSWORD
    unset RESTIC_PASSWORD_FILE
fi

# Probe repository; initialize on "unable to open repository" / uninitialized state
if ! probe_out="$(restic cat config 2>&1)"; then
    case "${probe_out}" in
        *"unable to open repository"*|*"unable to open config file"*|*"Is there a repository at the following location"*|*"does not exist"*)
            init_msg="Repository ${RESTIC_REPOSITORY} not initialized; running restic init"
            echo "restic-backup: ${init_msg}"
            logger -t restic-backup "${init_msg}" 2>/dev/null || true
            restic init
            ;;
        *)
            echo "${probe_out}" >&2
            logger -t restic-backup "ERROR: Failed to probe repository ${RESTIC_REPOSITORY}" 2>/dev/null || true
            exit 1
            ;;
    esac
fi

# Assemble backup paths: $BACKUP_PATHS plus any existing /home/*/appdata directories
# shellcheck disable=SC2086
set -- ${BACKUP_PATHS}
for appdata_dir in /home/*/appdata; do
    if [ -d "${appdata_dir}" ]; then
        set -- "$@" "${appdata_dir}"
    fi
done

host_name="$(hostname)"

if [ -n "${RESTIC_OPTIONS}" ]; then
    # shellcheck disable=SC2086
    restic backup \
        --exclude-file=/etc/restic/excludes.txt \
        --host "${host_name}" \
        ${RESTIC_OPTIONS} \
        "$@"
else
    restic backup \
        --exclude-file=/etc/restic/excludes.txt \
        --host "${host_name}" \
        "$@"
fi

restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

summary_msg="Restic backup and retention prune completed for host ${host_name} (${RESTIC_REPOSITORY})"
echo "restic-backup: ${summary_msg}"
logger -t restic-backup "${summary_msg}" 2>/dev/null || true
