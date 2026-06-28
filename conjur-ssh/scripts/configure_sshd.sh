#!/usr/bin/env bash
# =============================================================================
# configure_sshd.sh — Configure an SSH server to trust the Conjur CA
#
# Run this script on each target host (or via Ansible/Chef/Puppet) to:
#   1. Install the Conjur CA public key as a TrustedUserCAKeys source
#   2. Configure principals (optional) to map certificate principals to
#      local OS usernames
#   3. Reload sshd to apply changes
#
# After running this script, users with a valid Conjur-issued certificate
# can SSH to this host WITHOUT a password or static authorized_keys entry.
#
# Usage:
#   # Retrieve CA public key from Conjur and configure this host:
#   CA_PUBKEY=$(conjur variable get -i ssh/ca/public-key)
#   ./configure_sshd.sh --ca-pubkey "${CA_PUBKEY}"
#
#   # Or run on a remote host via SSH:
#   ssh admin@target-host 'bash -s' < configure_sshd.sh -- \
#       --ca-pubkey "$(conjur variable get -i ssh/ca/public-key)"
# =============================================================================

set -euo pipefail

CA_PUBKEY=""
CA_PUBKEY_PATH="/etc/ssh/conjur_ca.pub"
PRINCIPALS_FILE="/etc/ssh/auth_principals"
SSHD_CONFIG="/etc/ssh/sshd_config"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --ca-pubkey)     CA_PUBKEY="${2}"; shift 2 ;;
        --ca-key-path)   CA_PUBKEY_PATH="${2}"; shift 2 ;;
        --sshd-config)   SSHD_CONFIG="${2}"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        *) echo "Unknown argument: ${1}"; exit 1 ;;
    esac
done

if [[ -z "${CA_PUBKEY}" ]]; then
    echo "Usage: $0 --ca-pubkey <ca_public_key_string>"
    echo ""
    echo "Retrieve the CA public key from Conjur first:"
    echo "  CA_PUBKEY=\$(conjur variable get -i ssh/ca/public-key)"
    echo "  $0 --ca-pubkey \"\${CA_PUBKEY}\""
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: This script must run as root or with sudo."
    exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }
dry() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY RUN] $*"
    else
        eval "$*"
    fi
}

log "Configuring SSH server to trust Conjur CA"
log "Config file : ${SSHD_CONFIG}"
log "CA key path : ${CA_PUBKEY_PATH}"
log ""

# -------------------------------------------------------------------------
# 1. Install the CA public key.
# -------------------------------------------------------------------------
log "[1/4] Installing CA public key..."
dry "echo '${CA_PUBKEY}' > '${CA_PUBKEY_PATH}'"
dry "chmod 644 '${CA_PUBKEY_PATH}'"
log "      Installed: ${CA_PUBKEY_PATH}"

# -------------------------------------------------------------------------
# 2. Configure sshd to use the CA key as TrustedUserCAKeys.
# -------------------------------------------------------------------------
log "[2/4] Updating ${SSHD_CONFIG}..."

SSHD_DIRECTIVES=(
    "TrustedUserCAKeys ${CA_PUBKEY_PATH}"
    "AuthorizedPrincipalsFile ${PRINCIPALS_FILE}/%u"
    "PubkeyAuthentication yes"
)

BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
dry "cp '${SSHD_CONFIG}' '${BACKUP}'"
log "      Backed up sshd_config to: ${BACKUP}"

for DIRECTIVE in "${SSHD_DIRECTIVES[@]}"; do
    KEY="${DIRECTIVE%% *}"
    if grep -qE "^${KEY}\s" "${SSHD_CONFIG}" 2>/dev/null; then
        dry "sed -i 's|^${KEY}.*|${DIRECTIVE}|' '${SSHD_CONFIG}'"
        log "      Updated: ${DIRECTIVE}"
    else
        dry "echo '${DIRECTIVE}' >> '${SSHD_CONFIG}'"
        log "      Added:   ${DIRECTIVE}"
    fi
done

# -------------------------------------------------------------------------
# 3. Create the principals directory (maps certificate principals to users).
# -------------------------------------------------------------------------
log "[3/4] Setting up authorized principals..."
dry "mkdir -p '${PRINCIPALS_FILE}'"
dry "chmod 755 '${PRINCIPALS_FILE}'"

# Create sample principal files for common OS users.
# The certificate principal must be listed here for login to succeed.
SAMPLE_PRINCIPALS=(
    "root:all-servers"
    "ubuntu:web-servers"
    "ec2-user:web-servers"
    "deploy:web-servers,database-servers"
    "monitor:all-servers"
)

for ENTRY in "${SAMPLE_PRINCIPALS[@]}"; do
    OS_USER="${ENTRY%%:*}"
    PRINCIPALS="${ENTRY#*:}"
    PRINCIPALS_FORMATTED=$(echo "${PRINCIPALS}" | tr ',' '\n')
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "  [DRY RUN] echo '${PRINCIPALS_FORMATTED}' > '${PRINCIPALS_FILE}/${OS_USER}'"
    else
        echo "${PRINCIPALS_FORMATTED}" > "${PRINCIPALS_FILE}/${OS_USER}"
        chmod 644 "${PRINCIPALS_FILE}/${OS_USER}"
    fi
    log "      Principal file: ${PRINCIPALS_FILE}/${OS_USER} → [${PRINCIPALS}]"
done

# -------------------------------------------------------------------------
# 4. Validate and reload sshd.
# -------------------------------------------------------------------------
log "[4/4] Validating and reloading sshd..."
if [[ "${DRY_RUN}" == "false" ]]; then
    if sshd -t 2>&1; then
        log "      sshd config validation: PASSED"
        systemctl reload sshd 2>/dev/null || service sshd reload 2>/dev/null || true
        log "      sshd reloaded successfully."
    else
        log "ERROR: sshd config validation failed — reverting to backup."
        cp "${BACKUP}" "${SSHD_CONFIG}"
        exit 1
    fi
else
    log "      [DRY RUN] Would run: sshd -t && systemctl reload sshd"
fi

log ""
log "======================================================================"
log " Configuration complete. This host now trusts the Conjur SSH CA."
log " Users with a valid Conjur-issued certificate can authenticate without"
log " a password or entry in authorized_keys."
log "======================================================================"
