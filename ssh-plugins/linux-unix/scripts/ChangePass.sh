#!/usr/bin/env bash
# =============================================================================
# ChangePass.sh — Helper script for Linux/Unix SSH CPM plugin
#
# Called by Process.ini when CPM needs additional logic beyond simple
# prompt/response sequences. This script is placed on the target host
# and invoked over the SSH session.
#
# Usage (invoked by CPM over SSH):
#   bash ChangePass.sh <username> <new_password>
#
# Exit codes:
#   0 — password changed successfully
#   1 — invalid arguments
#   2 — passwd command failed
# =============================================================================

set -euo pipefail

TARGET_USER="${1:-}"
NEW_PASSWORD="${2:-}"

if [[ -z "${TARGET_USER}" || -z "${NEW_PASSWORD}" ]]; then
    echo "ERROR: Usage: $0 <username> <new_password>" >&2
    exit 1
fi

# Validate the username exists on the system.
if ! id "${TARGET_USER}" &>/dev/null; then
    echo "ERROR: User '${TARGET_USER}' does not exist on this system." >&2
    exit 1
fi

# Enforce minimum password length as a local guard (CPM enforces this too).
if [[ "${#NEW_PASSWORD}" -lt 12 ]]; then
    echo "ERROR: Password must be at least 12 characters." >&2
    exit 1
fi

# Change the password using chpasswd (non-interactive, suitable for scripting).
# chpasswd reads username:password pairs from stdin.
if echo "${TARGET_USER}:${NEW_PASSWORD}" | chpasswd 2>/dev/null; then
    echo "SUCCESS: Password for '${TARGET_USER}' changed successfully."
    exit 0
fi

# Fallback: use passwd with expect-style heredoc if chpasswd is unavailable.
if command -v passwd &>/dev/null; then
    if passwd --stdin "${TARGET_USER}" <<< "${NEW_PASSWORD}" 2>/dev/null; then
        echo "SUCCESS: Password for '${TARGET_USER}' changed via passwd."
        exit 0
    fi
fi

echo "ERROR: Failed to change password for '${TARGET_USER}'." >&2
exit 2
