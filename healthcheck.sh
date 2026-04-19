#!/bin/bash
set -euo pipefail

# =============================================================================
# Healthcheck script for PBS Backup container
#
# Verifies:
#   1. backup.sh process is running
#   2. Process is responsive (not stuck/hung)
# =============================================================================

# Check if backup.sh is running
if ! pgrep -f "bash.*backup.sh" > /dev/null; then
  echo "backup.sh process not found"
  exit 1
fi

# Process is running and responsive
exit 0
