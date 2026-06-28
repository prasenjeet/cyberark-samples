#!/usr/bin/env bash
# =============================================================================
# detect_prompts.sh — Capture SSH session output to identify CLI prompts.
#
# Run this script from a machine that has network access to the target host
# BEFORE writing Process.ini. It opens an interactive SSH session, injects
# a sequence of commands with delays, and saves the full transcript so you
# can identify the exact prompt text emitted by the application.
#
# Usage:
#   ./detect_prompts.sh <host> <port> <username>
#
# The raw transcript is saved to: /tmp/cyberark_prompt_capture_<timestamp>.txt
# =============================================================================

set -uo pipefail

HOST="${1:-}"
PORT="${2:-22}"
USERNAME="${3:-}"

if [[ -z "${HOST}" || -z "${USERNAME}" ]]; then
    echo "Usage: $0 <host> <port> <username>"
    echo "Example: $0 192.168.1.50 22 appuser"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TRANSCRIPT_FILE="/tmp/cyberark_prompt_capture_${TIMESTAMP}.txt"

echo "======================================================================"
echo " CyberArk Plugin — SSH Prompt Detection"
echo "======================================================================"
echo " Target : ${HOST}:${PORT}"
echo " User   : ${USERNAME}"
echo " Output : ${TRANSCRIPT_FILE}"
echo "======================================================================"
echo ""
echo "This will open an interactive SSH session. The full output will be"
echo "saved to the transcript file for analysis. Type your application's"
echo "commands as normal, then type 'exit' or 'quit' to end the session."
echo ""
echo "Press Enter to start..."
read -r

# Use 'script' to capture the full terminal session including prompts.
# The -q flag suppresses the 'Script started' banner.
if command -v script &>/dev/null; then
    script -q -c "ssh -p ${PORT} -o StrictHostKeyChecking=no ${USERNAME}@${HOST}" "${TRANSCRIPT_FILE}"
else
    # Fallback: use SSH with pseudo-TTY and tee (less accurate but works).
    ssh -t -p "${PORT}" -o StrictHostKeyChecking=no "${USERNAME}@${HOST}" 2>&1 | tee "${TRANSCRIPT_FILE}"
fi

echo ""
echo "======================================================================"
echo " Session ended. Transcript saved to: ${TRANSCRIPT_FILE}"
echo "======================================================================"
echo ""
echo "Next steps:"
echo "  1. Review the transcript to identify exact prompt strings."
echo "  2. Build regex patterns from the prompts (use | for alternatives)."
echo "  3. Fill in Process.ini ExpectedOutputN values with those patterns."
echo "  4. Validate with: scripts/test_session.sh"
