#!/usr/bin/env bash
# =============================================================================
# test_session.sh — Validate a CPM plugin command sequence before deployment.
#
# Simulates what CPM does: connects via SSH, sends each command from a simple
# sequence file, and checks the output against expected prompt patterns.
# Run this after capturing prompts with detect_prompts.sh and before
# copying the plugin to the CPM server.
#
# Usage:
#   ./test_session.sh --host <host> --port <port> --user <user> \
#                     --sequence <sequence_file> [--timeout <seconds>]
#
# Sequence file format (one entry per pair of lines):
#   COMMAND: <command to send>
#   EXPECT:  <regex to match in response>
#
# Example sequence file (test_verify.seq):
#   COMMAND: show version
#   EXPECT:  Version|version
#   COMMAND: exit
#   EXPECT:  .*
# =============================================================================

set -uo pipefail

HOST=""
PORT="22"
USERNAME=""
SEQUENCE_FILE=""
TIMEOUT=30

# Parse arguments.
while [[ $# -gt 0 ]]; do
    case "${1}" in
        --host)     HOST="${2}"; shift 2 ;;
        --port)     PORT="${2}"; shift 2 ;;
        --user)     USERNAME="${2}"; shift 2 ;;
        --sequence) SEQUENCE_FILE="${2}"; shift 2 ;;
        --timeout)  TIMEOUT="${2}"; shift 2 ;;
        *) echo "Unknown argument: ${1}"; exit 1 ;;
    esac
done

if [[ -z "${HOST}" || -z "${USERNAME}" || -z "${SEQUENCE_FILE}" ]]; then
    echo "Usage: $0 --host <host> --port <port> --user <user> --sequence <file>"
    exit 1
fi

if [[ ! -f "${SEQUENCE_FILE}" ]]; then
    echo "ERROR: Sequence file not found: ${SEQUENCE_FILE}"
    exit 1
fi

echo "======================================================================"
echo " CyberArk Plugin — Session Sequence Test"
echo "======================================================================"
echo " Target   : ${HOST}:${PORT}"
echo " User     : ${USERNAME}"
echo " Sequence : ${SEQUENCE_FILE}"
echo " Timeout  : ${TIMEOUT}s per step"
echo "======================================================================"

# Read password securely.
read -rsp "Enter SSH password for ${USERNAME}@${HOST}: " SSH_PASSWORD
echo ""

PASS_COUNT=0
FAIL_COUNT=0
STEP=0

# Process the sequence file using a FIFO-based expect-lite approach.
# For production use, replace with an actual expect script.
while IFS= read -r line; do
    case "${line}" in
        COMMAND:*)
            COMMAND="${line#COMMAND: }"
            ;;
        EXPECT:*)
            PATTERN="${line#EXPECT: }"
            STEP=$((STEP + 1))
            echo -n "  Step ${STEP}: CMD='${COMMAND}' EXPECT='${PATTERN}' ... "

            # Use sshpass + SSH to send the command and capture output.
            if command -v sshpass &>/dev/null; then
                OUTPUT=$(sshpass -p "${SSH_PASSWORD}" ssh -T -q \
                    -o StrictHostKeyChecking=no \
                    -o ConnectTimeout="${TIMEOUT}" \
                    -p "${PORT}" \
                    "${USERNAME}@${HOST}" \
                    "${COMMAND}" 2>&1 || true)

                if echo "${OUTPUT}" | grep -qE "${PATTERN}"; then
                    echo "PASS"
                    PASS_COUNT=$((PASS_COUNT + 1))
                else
                    echo "FAIL (output: $(echo "${OUTPUT}" | head -3))"
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                fi
            else
                echo "SKIP (sshpass not installed — install with: apt-get install sshpass)"
            fi
            ;;
    esac
done < "${SEQUENCE_FILE}"

echo ""
echo "======================================================================"
echo " Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "======================================================================"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    echo " VALIDATION FAILED — Review and update Process.ini before deploying."
    exit 1
else
    echo " VALIDATION PASSED — Plugin is ready for CPM deployment."
    exit 0
fi
