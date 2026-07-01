#!/usr/bin/env bash
# =============================================================================
# reconcile_dispatcher.sh — Multi-account SSH key reconcile dispatcher
#
# Called by CPM as the PreCommandScript for the RECONCILESSH_MULTIKEY section.
# Iterates over up to three reconcile accounts in priority order, trying each
# until one successfully resets the managed account's password.
#
# Supported authentication methods per account:
#   Password — connects using the account's Vault password via sshpass
#   Key      — connects using the account's Vault credential as an SSH private
#              key (PEM content), written to a secure temp file and deleted
#              immediately after use
#
# Usage (called by CPM — do not invoke directly in production):
#   reconcile_dispatcher.sh \
#     <address> <port> <target_user> <new_password> \
#     <recon1_user> <recon1_cred> <recon1_auth_method> \
#     [<recon2_user> <recon2_cred> <recon2_auth_method>] \
#     [<recon3_user> <recon3_cred> <recon3_auth_method>]
#
# <recon_auth_method> is "Key" or "Password" (case-insensitive).
#
# Output (stdout, parsed by CPM):
#   RECON_SUCCESS:<account_index>:<recon_username>  — on success
#   RECON_FAILURE:<error_summary>                   — when all accounts fail
#
# Exit codes:
#   0 — password reset successfully
#   1 — all accounts exhausted / all attempts failed
#   2 — argument validation failure
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 7 ]]; then
    echo "RECON_FAILURE: Insufficient arguments (got $#, minimum 7)" >&2
    echo "Usage: $0 <address> <port> <target_user> <new_password> <recon1_user> <recon1_cred> <recon1_auth_method> [...]" >&2
    exit 2
fi

TARGET_ADDRESS="${1}"
TARGET_PORT="${2}"
TARGET_USER="${3}"
NEW_PASSWORD="${4}"

# Pack remaining args into reconcile account triplets: user, cred, auth_method
shift 4
RECON_ACCOUNTS=("$@")

# ---------------------------------------------------------------------------
# Helper: secure temp file with automatic cleanup
# ---------------------------------------------------------------------------
TMPFILES=()
cleanup() {
    for f in "${TMPFILES[@]:-}"; do
        [[ -f "${f}" ]] && rm -f "${f}"
    done
}
trap cleanup EXIT INT TERM

make_temp_key() {
    local content="${1}"
    local tmpfile
    tmpfile=$(mktemp -t cyberark_recon_key.XXXXXX)
    chmod 600 "${tmpfile}"
    printf '%s\n' "${content}" > "${tmpfile}"
    TMPFILES+=("${tmpfile}")
    echo "${tmpfile}"
}

# ---------------------------------------------------------------------------
# Helper: upload ReconcilePass.sh to the target and execute it
# ---------------------------------------------------------------------------
RECON_SCRIPT_LOCAL="$(dirname "${BASH_SOURCE[0]}")/ReconcilePass.sh"
RECON_SCRIPT_REMOTE="/tmp/.cark_recon_$$.sh"

upload_and_run_recon() {
    local ssh_opts=("${@}")
    # Upload the reconcile script to the target.
    if ! scp "${ssh_opts[@]}" "${RECON_SCRIPT_LOCAL}" "${RECON_SCRIPT_REMOTE}" 2>/dev/null; then
        return 1
    fi
    # Execute it remotely.
    if ssh "${ssh_opts[@]}" "bash ${RECON_SCRIPT_REMOTE} '${TARGET_USER}' '${NEW_PASSWORD}'; rm -f ${RECON_SCRIPT_REMOTE}" 2>/dev/null \
        | grep -q "SUCCESS"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Helper: common SSH options
# ---------------------------------------------------------------------------
base_ssh_opts=(
    -o StrictHostKeyChecking=no
    -o BatchMode=yes
    -o ConnectTimeout=15
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
    -p "${TARGET_PORT}"
)

# ---------------------------------------------------------------------------
# Helper: attempt reconcile via PASSWORD authentication
# ---------------------------------------------------------------------------
try_password_recon() {
    local recon_user="${1}"
    local recon_pass="${2}"
    local acct_index="${3}"

    log_attempt "${acct_index}" "${recon_user}" "Password"

    if ! command -v sshpass &>/dev/null; then
        log_warn "sshpass not found — cannot attempt password reconcile for account ${acct_index}."
        return 1
    fi

    local ssh_opts=("${base_ssh_opts[@]}" "${recon_user}@${TARGET_ADDRESS}")

    if SSHPASS="${recon_pass}" sshpass -e ssh "${base_ssh_opts[@]}" \
        "${recon_user}@${TARGET_ADDRESS}" \
        "bash -s" <<< "$(cat "${RECON_SCRIPT_LOCAL}")" \
        -- "${TARGET_USER}" "${NEW_PASSWORD}" 2>/dev/null \
        | grep -q "SUCCESS"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Helper: attempt reconcile via SSH KEY authentication
# ---------------------------------------------------------------------------
try_key_recon() {
    local recon_user="${1}"
    local key_content="${2}"
    local acct_index="${3}"

    log_attempt "${acct_index}" "${recon_user}" "Key"

    # Validate the key content looks like a PEM private key.
    if ! echo "${key_content}" | grep -q "BEGIN.*PRIVATE KEY"; then
        log_warn "Account ${acct_index} credential does not look like a PEM private key — skipping."
        return 1
    fi

    local key_file
    key_file=$(make_temp_key "${key_content}")

    local ssh_opts=(
        "${base_ssh_opts[@]}"
        -o IdentitiesOnly=yes
        -i "${key_file}"
    )

    # Upload ReconcilePass.sh via scp and execute it.
    if scp "${ssh_opts[@]}" "${RECON_SCRIPT_LOCAL}" \
        "${recon_user}@${TARGET_ADDRESS}:${RECON_SCRIPT_REMOTE}" 2>/dev/null && \
       ssh "${ssh_opts[@]}" "${recon_user}@${TARGET_ADDRESS}" \
        "bash '${RECON_SCRIPT_REMOTE}' '${TARGET_USER}' '${NEW_PASSWORD}'; rm -f '${RECON_SCRIPT_REMOTE}'" \
        2>/dev/null | grep -q "SUCCESS"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Logging helpers (stdout goes to CPM log)
# ---------------------------------------------------------------------------
log()      { echo "[$(date '+%H:%M:%S')] [RECON_DISPATCHER] $*"; }
log_warn() { echo "[$(date '+%H:%M:%S')] [RECON_DISPATCHER] WARN: $*"; }

log_attempt() {
    local idx="${1}" user="${2}" method="${3}"
    log "Attempting reconcile — account ${idx} (${user}) via ${method} auth ..."
}

# ---------------------------------------------------------------------------
# Main: iterate reconcile accounts
# ---------------------------------------------------------------------------
ACCOUNT_INDEX=0
TOTAL_ACCOUNTS=$(( ${#RECON_ACCOUNTS[@]} / 3 ))

if [[ "${TOTAL_ACCOUNTS}" -eq 0 ]]; then
    echo "RECON_FAILURE: No reconcile accounts provided." >&2
    exit 1
fi

log "Starting multi-account reconcile for user '${TARGET_USER}' on ${TARGET_ADDRESS}:${TARGET_PORT}"
log "Total reconcile accounts configured: ${TOTAL_ACCOUNTS}"

for (( i=0; i < ${#RECON_ACCOUNTS[@]}; i+=3 )); do
    RECON_USER="${RECON_ACCOUNTS[i]:-}"
    RECON_CRED="${RECON_ACCOUNTS[i+1]:-}"
    RECON_METHOD="${RECON_ACCOUNTS[i+2]:-Password}"
    ACCOUNT_INDEX=$(( i/3 + 1 ))

    # Skip unconfigured accounts (CPM passes empty strings for unused ExtraPassN).
    if [[ -z "${RECON_USER}" ]]; then
        log "Account ${ACCOUNT_INDEX} not configured — skipping."
        continue
    fi

    log "--- Account ${ACCOUNT_INDEX}: ${RECON_USER} [${RECON_METHOD}] ---"

    case "${RECON_METHOD,,}" in
        key)
            if try_key_recon "${RECON_USER}" "${RECON_CRED}" "${ACCOUNT_INDEX}"; then
                log "SUCCESS: Reconcile completed using account ${ACCOUNT_INDEX} (${RECON_USER}) via Key auth."
                echo "RECON_SUCCESS:${ACCOUNT_INDEX}:${RECON_USER}"
                exit 0
            fi
            log "Account ${ACCOUNT_INDEX} Key auth failed — trying next account."
            ;;
        password|"")
            if try_password_recon "${RECON_USER}" "${RECON_CRED}" "${ACCOUNT_INDEX}"; then
                log "SUCCESS: Reconcile completed using account ${ACCOUNT_INDEX} (${RECON_USER}) via Password auth."
                echo "RECON_SUCCESS:${ACCOUNT_INDEX}:${RECON_USER}"
                exit 0
            fi
            log "Account ${ACCOUNT_INDEX} Password auth failed — trying next account."
            ;;
        *)
            log_warn "Unknown auth method '${RECON_METHOD}' for account ${ACCOUNT_INDEX} — skipping."
            ;;
    esac
done

log "All ${TOTAL_ACCOUNTS} reconcile account(s) exhausted without success."
echo "RECON_FAILURE: All ${TOTAL_ACCOUNTS} reconcile account(s) failed for user '${TARGET_USER}' on ${TARGET_ADDRESS}"
exit 1
