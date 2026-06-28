#!/usr/bin/env bash
# =============================================================================
# setup_ca.sh — Initialize Conjur as an SSH Certificate Authority
#
# This script:
#   1. Generates an Ed25519 SSH CA key pair
#   2. Stores the private key in Conjur (never written to disk unencrypted)
#   3. Stores the public key in Conjur (for distribution to target hosts)
#   4. Sets the default certificate TTL
#
# Prerequisites:
#   - conjur CLI authenticated and connected to your Conjur server
#   - ssh-keygen (OpenSSH) installed locally
#   - The ssh-ca-policy.yml has already been loaded into Conjur
#
# Usage:
#   ./setup_ca.sh [--ttl <default_ttl>]
#
# Example:
#   ./setup_ca.sh --ttl 8h
# =============================================================================

set -euo pipefail

DEFAULT_TTL="8h"

while [[ $# -gt 0 ]]; do
    case "${1}" in
        --ttl) DEFAULT_TTL="${2}"; shift 2 ;;
        *) echo "Unknown argument: ${1}"; exit 1 ;;
    esac
done

CONJUR_CA_KEY_VAR="ssh/ca/private-key"
CONJUR_CA_PUB_VAR="ssh/ca/public-key"
CONJUR_CA_TTL_VAR="ssh/ca/certificate-ttl"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

CA_KEY="${TMPDIR}/ssh_ca_key"
CA_PUB="${TMPDIR}/ssh_ca_key.pub"

echo "======================================================================"
echo " Conjur SSH CA Initialization"
echo "======================================================================"
echo ""

# Verify Conjur CLI is authenticated.
echo "[1/5] Checking Conjur connectivity..."
if ! conjur whoami &>/dev/null; then
    echo "ERROR: Not authenticated to Conjur. Run 'conjur init' and 'conjur login' first."
    exit 1
fi
echo "      OK ($(conjur whoami | grep -oP '(?<=username: )\S+'))"

# Check if the CA key already exists to prevent accidental rotation.
echo ""
echo "[2/5] Checking for existing CA key..."
EXISTING_KEY=$(conjur variable get -i "${CONJUR_CA_KEY_VAR}" 2>/dev/null || true)
if [[ -n "${EXISTING_KEY}" ]]; then
    echo ""
    echo "WARNING: An existing CA private key was found in Conjur."
    echo "         Rotating the CA key will invalidate ALL currently issued certificates."
    echo "         Target hosts will need to be updated with the new public key."
    echo ""
    read -rp "Are you sure you want to rotate the CA key? (yes/no): " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "Aborted. No changes were made."
        exit 0
    fi
fi

# Generate the CA key pair in a secure temp directory.
echo ""
echo "[3/5] Generating Ed25519 CA key pair (in memory only)..."
ssh-keygen -t ed25519 -f "${CA_KEY}" -N "" -C "conjur-ssh-ca-$(date +%Y%m%d)" -q
echo "      Key pair generated."

# Store the private key in Conjur.
echo ""
echo "[4/5] Storing keys in Conjur..."
conjur variable set -i "${CONJUR_CA_KEY_VAR}" -v "$(cat "${CA_KEY}")"
echo "      Private key stored in: ${CONJUR_CA_KEY_VAR}"

conjur variable set -i "${CONJUR_CA_PUB_VAR}" -v "$(cat "${CA_PUB}")"
echo "      Public key stored in:  ${CONJUR_CA_PUB_VAR}"

conjur variable set -i "${CONJUR_CA_TTL_VAR}" -v "${DEFAULT_TTL}"
echo "      Default TTL set to:    ${DEFAULT_TTL}"

# Display the public key for distribution to target hosts.
echo ""
echo "[5/5] CA initialization complete."
echo ""
echo "======================================================================"
echo " Next step: distribute the CA public key to all target SSH servers."
echo " Run the following on each target host:"
echo ""
echo "   ./configure_sshd.sh --ca-pubkey \"$(cat "${CA_PUB}")\""
echo ""
echo " Or use the conjur CLI to retrieve it later:"
echo ""
echo "   conjur variable get -i ${CONJUR_CA_PUB_VAR}"
echo "======================================================================"
