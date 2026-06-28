#!/usr/bin/env bash
# =============================================================================
# ReconcilePass.sh — Force-reset an account password using a privileged account.
#
# Executed on the target host by the privileged reconcile account (e.g., root
# or a sudo-enabled admin). Resets the managed account to a new password
# supplied by CPM without requiring knowledge of the current password.
#
# Usage:
#   bash ReconcilePass.sh <target_username> <new_password>
#
# Exit codes:
#   0 — password reset successfully
#   1 — invalid arguments or user not found
#   2 — insufficient privileges
#   3 — password change failed
# =============================================================================

set -uo pipefail

TARGET_USER="${1:-}"
NEW_PASSWORD="${2:-}"

if [[ -z "${TARGET_USER}" || -z "${NEW_PASSWORD}" ]]; then
    echo "ERROR: Usage: $0 <target_username> <new_password>" >&2
    exit 1
fi

# Verify caller has root/sudo access to reset another account's password.
if [[ "${EUID}" -ne 0 ]]; then
    if ! sudo -n true 2>/dev/null; then
        echo "ERROR: This script must run as root or with passwordless sudo." >&2
        exit 2
    fi
    SUDO="sudo"
else
    SUDO=""
fi

# Verify the target account exists.
if ! id "${TARGET_USER}" &>/dev/null; then
    echo "ERROR: User '${TARGET_USER}' does not exist." >&2
    exit 1
fi

# Unlock the account if it is locked before setting the new password.
${SUDO} passwd -u "${TARGET_USER}" 2>/dev/null || true

# Reset the password using chpasswd (preferred — handles all PAM modules).
if echo "${TARGET_USER}:${NEW_PASSWORD}" | ${SUDO} chpasswd 2>/dev/null; then
    echo "SUCCESS: Password for '${TARGET_USER}' reset via chpasswd."
    exit 0
fi

# Fallback: use passwd --stdin (RHEL/CentOS).
if ${SUDO} passwd --stdin "${TARGET_USER}" <<< "${NEW_PASSWORD}" 2>/dev/null; then
    echo "SUCCESS: Password for '${TARGET_USER}' reset via passwd --stdin."
    exit 0
fi

# Fallback: use usermod -p with a pre-hashed password (last resort).
HASHED=$(python3 -c "import crypt; print(crypt.crypt('${NEW_PASSWORD}', crypt.mksalt(crypt.METHOD_SHA512)))" 2>/dev/null)
if [[ -n "${HASHED}" ]]; then
    if ${SUDO} usermod -p "${HASHED}" "${TARGET_USER}" 2>/dev/null; then
        echo "SUCCESS: Password for '${TARGET_USER}' reset via usermod."
        exit 0
    fi
fi

echo "ERROR: All password reset methods failed for '${TARGET_USER}'." >&2
exit 3
