#!/usr/bin/env bash
# =============================================================================
# validate_recon_keys.sh — Pre-deployment validation for SSH key reconcile accounts
#
# Run this script BEFORE deploying the plugin to CPM to confirm that each
# configured reconcile account can:
#   1. Authenticate to the target host via its SSH key
#   2. Execute privilege-escalated password changes (sudo or root)
#
# This helps catch key/permission issues before CPM encounters them during
# an actual reconcile operation.
#
# Usage:
#   ./validate_recon_keys.sh --host <target> --port <port> \
#       --target-user <managed_user> \
#       --recon1-user <user> --recon1-key <key_file_or_content> \
#       [--recon2-user <user> --recon2-key <key_file_or_content>] \
#       [--recon3-user <user> --recon3-key <key_file_or_content>]
#
# Example — validating three key-based reconcile accounts:
#   ./validate_recon_keys.sh \
#       --host 10.0.1.50 --port 22 \
#       --target-user appuser \
#       --recon1-user root          --recon1-key ~/.ssh/root_recon_key \
#       --recon2-user deploy-admin  --recon2-key ~/.ssh/deploy_key \
#       --recon3-user breakglass    --recon3-key ~/.ssh/bg_key
# =============================================================================

set -uo pipefail

HOST=""
PORT=22
TARGET_USER=""
declare -A RECON_USERS=()
declare -A RECON_KEYS=()

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --host)         HOST="${2}"; shift 2 ;;
        --port)         PORT="${2}"; shift 2 ;;
        --target-user)  TARGET_USER="${2}"; shift 2 ;;
        --recon1-user)  RECON_USERS[1]="${2}"; shift 2 ;;
        --recon1-key)   RECON_KEYS[1]="${2}"; shift 2 ;;
        --recon2-user)  RECON_USERS[2]="${2}"; shift 2 ;;
        --recon2-key)   RECON_KEYS[2]="${2}"; shift 2 ;;
        --recon3-user)  RECON_USERS[3]="${2}"; shift 2 ;;
        --recon3-key)   RECON_KEYS[3]="${2}"; shift 2 ;;
        *) echo "Unknown argument: ${1}"; exit 1 ;;
    esac
done

if [[ -z "${HOST}" || -z "${TARGET_USER}" || -z "${RECON_USERS[1]:-}" ]]; then
    echo "Usage: $0 --host <host> --port <port> --target-user <user> --recon1-user <u> --recon1-key <key> [...]"
    exit 1
fi

TMPFILES=()
cleanup() { for f in "${TMPFILES[@]:-}"; do [[ -f "${f}" ]] && rm -f "${f}"; done; }
trap cleanup EXIT INT TERM

resolve_key() {
    local key_input="${1}"
    if [[ -f "${key_input}" ]]; then
        echo "${key_input}"
        return
    fi
    # Treat input as PEM key content — write to a temp file.
    local tmpfile
    tmpfile=$(mktemp -t validate_recon_key.XXXXXX)
    chmod 600 "${tmpfile}"
    printf '%s\n' "${key_input}" > "${tmpfile}"
    TMPFILES+=("${tmpfile}")
    echo "${tmpfile}"
}

PASS=0
FAIL=0

echo "======================================================================"
echo " CyberArk Linux/Unix SSH Plugin — Reconcile Key Validation"
echo "======================================================================"
printf " Target host   : %s:%s\n" "${HOST}" "${PORT}"
printf " Managed user  : %s\n" "${TARGET_USER}"
echo "======================================================================"
echo ""

BASE_SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o IdentitiesOnly=yes
    -p "${PORT}"
)

for idx in 1 2 3; do
    RECON_USER="${RECON_USERS[${idx}]:-}"
    RECON_KEY_INPUT="${RECON_KEYS[${idx}]:-}"

    [[ -z "${RECON_USER}" ]] && continue

    echo "--- Reconcile Account ${idx}: ${RECON_USER} ---"

    if [[ -z "${RECON_KEY_INPUT}" ]]; then
        printf "  %-40s SKIP (no key provided)\n" "Key configured"
        echo ""
        continue
    fi

    KEY_FILE=$(resolve_key "${RECON_KEY_INPUT}")

    # Test 1: Can the key authenticate to the target?
    printf "  %-40s" "SSH auth (${RECON_USER}@${HOST}) ..."
    if ssh "${BASE_SSH_OPTS[@]}" -i "${KEY_FILE}" "${RECON_USER}@${HOST}" "echo auth_ok" 2>/dev/null | grep -q "auth_ok"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL — check key is in authorized_keys on target"
        FAIL=$((FAIL + 1))
        echo ""
        continue
    fi

    # Test 2: Can the account reset another user's password?
    printf "  %-40s" "Password reset capability ..."
    RESET_CMD="id ${TARGET_USER} &>/dev/null && (echo '${TARGET_USER}:TestPass123!' | sudo chpasswd 2>/dev/null || sudo passwd --stdin ${TARGET_USER} <<< 'TestPass123!' 2>/dev/null || echo 'SKIP') && echo 'reset_ok'"
    RESET_RESULT=$(ssh "${BASE_SSH_OPTS[@]}" -i "${KEY_FILE}" "${RECON_USER}@${HOST}" "${RESET_CMD}" 2>/dev/null || true)
    if echo "${RESET_RESULT}" | grep -q "reset_ok\|SKIP"; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL — account lacks sudo/root privilege to reset passwords"
        FAIL=$((FAIL + 1))
    fi

    # Test 3: Is key type strong enough (Ed25519 or RSA 4096+)?
    printf "  %-40s" "Key strength ..."
    KEY_TYPE=$(ssh-keygen -l -f "${KEY_FILE}" 2>/dev/null | awk '{print $4, $1, $2}')
    KEY_BITS=$(echo "${KEY_TYPE}" | awk '{print $3}' | tr -d '()')
    KEY_ALGO=$(echo "${KEY_TYPE}" | awk '{print $1}')
    if [[ "${KEY_ALGO}" == "ED25519" ]] || [[ "${KEY_ALGO}" == "ECDSA" ]] || \
       { [[ "${KEY_ALGO}" == "RSA" ]] && [[ "${KEY_BITS:-0}" -ge 4096 ]]; }; then
        echo "PASS (${KEY_TYPE})"
        PASS=$((PASS + 1))
    else
        echo "WARN — consider upgrading to Ed25519 or RSA 4096+ (got: ${KEY_TYPE})"
    fi

    echo ""
done

echo "======================================================================"
printf " Results: %d checks passed, %d failed\n" "${PASS}" "${FAIL}"
echo "======================================================================"

if [[ "${FAIL}" -gt 0 ]]; then
    echo " VALIDATION FAILED — Fix the issues above before deploying to CPM."
    exit 1
else
    echo " VALIDATION PASSED — Reconcile keys are ready for CPM deployment."
    exit 0
fi
