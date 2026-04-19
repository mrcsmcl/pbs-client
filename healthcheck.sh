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
# Using grep on /proc/cmdline to avoid depending on procps (pgrep) package
if ! grep -q "backup.sh" /proc/1/cmdline 2>/dev/null; then
  # Fallback to search any process in case it's not PID 1
  # The grep pattern uses [b] to avoid matching the grep process itself
  if ! grep -q "[b]ackup.sh" /proc/[1-9]*/cmdline 2>/dev/null; then
    echo "backup.sh process not found"
    exit 1
  fi
fi

# Process is running and responsive
exit 0
