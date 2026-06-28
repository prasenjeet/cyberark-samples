#!/usr/bin/env bash
# =============================================================================
# issue_certificate.sh — Request an SSH certificate from CyberArk Conjur
#
# This script:
#   1. Authenticates to Conjur (or uses an existing session)
#   2. Fetches the CA private key from Conjur
#   3. Signs the user's SSH public key to create a certificate
#   4. Writes the certificate next to the user's public key
#
# The certificate is short-lived. Users must re-run this script when it
# expires (or automate renewal in their shell profile).
#
# Usage:
#   ./issue_certificate.sh [--key <public_key_path>] [--ttl <duration>]
#                          [--principals <p1,p2>] [--identity <cert_identity>]
#
# Examples:
#   ./issue_certificate.sh
#   ./issue_certificate.sh --key ~/.ssh/id_ed25519.pub --ttl 2h
#   ./issue_certificate.sh --principals web-servers,database-servers --ttl 30m
#
# Outputs:
#   <key_path>-cert.pub  (e.g., ~/.ssh/id_ed25519-cert.pub)
# =============================================================================

set -euo pipefail

PUBLIC_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"
TTL=""
PRINCIPALS=""
CERT_IDENTITY=""
FORCE_REGEN_KEY=false

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --key)        PUBLIC_KEY_PATH="${2}"; shift 2 ;;
        --ttl)        TTL="${2}"; shift 2 ;;
        --principals) PRINCIPALS="${2}"; shift 2 ;;
        --identity)   CERT_IDENTITY="${2}"; shift 2 ;;
        --gen-key)    FORCE_REGEN_KEY=true; shift ;;
        *) echo "Unknown argument: ${1}"; exit 1 ;;
    esac
done

CONJUR_CA_KEY_VAR="ssh/ca/private-key"
CONJUR_CA_TTL_VAR="ssh/ca/certificate-ttl"
CERT_PATH="${PUBLIC_KEY_PATH%-cert.pub}-cert.pub"
CERT_PATH="${PUBLIC_KEY_PATH%.pub}-cert.pub"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# -------------------------------------------------------------------------
# 1. Generate a key pair if one does not exist.
# -------------------------------------------------------------------------
if [[ ! -f "${PUBLIC_KEY_PATH}" ]] || [[ "${FORCE_REGEN_KEY}" == "true" ]]; then
    PRIVATE_KEY_PATH="${PUBLIC_KEY_PATH%.pub}"
    echo "Generating new Ed25519 key pair at: ${PRIVATE_KEY_PATH}"
    ssh-keygen -t ed25519 -f "${PRIVATE_KEY_PATH}" -N "" -C "$(whoami)@$(hostname)-$(date +%Y%m%d)" -q
fi

# -------------------------------------------------------------------------
# 2. Authenticate to Conjur and retrieve the CA key.
# -------------------------------------------------------------------------
echo "Fetching CA private key from Conjur..."
CA_PRIVATE_KEY=$(conjur variable get -i "${CONJUR_CA_KEY_VAR}" 2>/dev/null)
if [[ -z "${CA_PRIVATE_KEY}" ]]; then
    echo "ERROR: Could not retrieve CA private key from Conjur."
    echo "       Verify you are authenticated: conjur whoami"
    echo "       Verify the policy is loaded and you have 'execute' permission on:"
    echo "       ${CONJUR_CA_KEY_VAR}"
    exit 1
fi

# -------------------------------------------------------------------------
# 3. Resolve the TTL.
# -------------------------------------------------------------------------
if [[ -z "${TTL}" ]]; then
    TTL=$(conjur variable get -i "${CONJUR_CA_TTL_VAR}" 2>/dev/null || echo "8h")
fi

# -------------------------------------------------------------------------
# 4. Determine the certificate identity.
# -------------------------------------------------------------------------
if [[ -z "${CERT_IDENTITY}" ]]; then
    CONJUR_USER=$(conjur whoami 2>/dev/null | grep -oP '(?<=username: )\S+' || echo "unknown")
    CERT_IDENTITY="${CONJUR_USER}@$(hostname)-$(date +%Y%m%d%H%M%S)"
fi

# -------------------------------------------------------------------------
# 5. Write the CA key to a temp file and sign the certificate.
# -------------------------------------------------------------------------
CA_KEY_FILE="${TMPDIR}/ca_key"
printf '%s' "${CA_PRIVATE_KEY}" > "${CA_KEY_FILE}"
chmod 600 "${CA_KEY_FILE}"

SSH_KEYGEN_ARGS=(
    -s "${CA_KEY_FILE}"
    -I "${CERT_IDENTITY}"
    -V "+${TTL}"
)

if [[ -n "${PRINCIPALS}" ]]; then
    SSH_KEYGEN_ARGS+=(-n "${PRINCIPALS}")
fi

# User certificate (as opposed to host certificate).
SSH_KEYGEN_ARGS+=(-t rsa-sha2-512)

echo "Signing certificate..."
ssh-keygen "${SSH_KEYGEN_ARGS[@]}" "${PUBLIC_KEY_PATH}" -q 2>/dev/null

# -------------------------------------------------------------------------
# 6. Verify and display the certificate.
# -------------------------------------------------------------------------
if [[ ! -f "${CERT_PATH}" ]]; then
    echo "ERROR: Certificate file not created at: ${CERT_PATH}"
    exit 1
fi

echo ""
echo "======================================================================"
echo " SSH Certificate Issued Successfully"
echo "======================================================================"
ssh-keygen -L -f "${CERT_PATH}"
echo ""
echo " Certificate path : ${CERT_PATH}"
echo " Expires in       : ${TTL}"
echo ""
echo " Connect with:"
echo "   ssh -i ${PUBLIC_KEY_PATH%.pub} <user>@<target-host>"
echo "======================================================================"
