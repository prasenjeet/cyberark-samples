#!/usr/bin/env bash
# =============================================================================
# VerifyPass.sh — Verify that a credential is valid on the local system.
#
# This script is uploaded to and executed on the target host by CPM
# as part of the Verify operation. It uses PAM (via `su`) to test
# whether the stored password authenticates successfully without
# actually changing any state.
#
# Usage:
#   bash VerifyPass.sh <username> <password>
#
# Exit codes:
#   0 — credential is valid
#   1 — credential is invalid or account is locked
#   2 — verification tool unavailable
# =============================================================================

set -uo pipefail

TARGET_USER="${1:-}"
PASSWORD="${2:-}"

if [[ -z "${TARGET_USER}" || -z "${PASSWORD}" ]]; then
    echo "ERROR: Usage: $0 <username> <password>" >&2
    exit 1
fi

# Verify the account exists.
if ! id "${TARGET_USER}" &>/dev/null; then
    echo "ERROR: User '${TARGET_USER}' not found." >&2
    exit 1
fi

# Check that the account is not locked.
ACCOUNT_STATUS=$(passwd -S "${TARGET_USER}" 2>/dev/null | awk '{print $2}')
if [[ "${ACCOUNT_STATUS}" == "L" || "${ACCOUNT_STATUS}" == "LK" ]]; then
    echo "ERROR: Account '${TARGET_USER}' is locked." >&2
    exit 1
fi

# Use 'su' with a no-op command to test the password.
# The '-c true' runs /bin/true, which exits 0 immediately on success.
if echo "${PASSWORD}" | su -c "true" - "${TARGET_USER}" 2>/dev/null; then
    echo "SUCCESS: Credential verified for '${TARGET_USER}'."
    exit 0
fi

# Alternative: use pam_auth via python3 if available.
if command -v python3 &>/dev/null; then
    python3 - "${TARGET_USER}" "${PASSWORD}" <<'PYEOF'
import sys
import pam

p = pam.pam()
if p.authenticate(sys.argv[1], sys.argv[2], service='login'):
    print("SUCCESS: PAM authentication succeeded.")
    sys.exit(0)
else:
    print("ERROR: PAM authentication failed.", file=sys.stderr)
    sys.exit(1)
PYEOF
    exit $?
fi

echo "ERROR: Could not verify credential — no suitable verification method found." >&2
exit 2
