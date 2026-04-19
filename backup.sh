#!/bin/bash
set -euo pipefail

# =============================================================================
# PBS Backup Script — Proxmox Backup Client wrapper for Docker Swarm
#
# Iterates over all subdirectories in BACKUP_PATH and creates a
# proxmox-backup-client pxar archive for each one.
#
# Required environment variables:
#   PBS_REPOSITORY   — PBS server connection string
#   PBS_PASSWORD     — API token or user password
#   PBS_FINGERPRINT  — Server TLS certificate fingerprint
#   BACKUP_PATH      — Host path mounted into the container (read-only)
#
# Optional:
#   BACKUP_INTERVAL  — Seconds between backup cycles (default: 43200 = 12h)
#   BACKUP_ID        — Prefix for backup-id (default: container hostname)
#   BACKUP_STATE_DIR — Directory for state/log files (default: /var/lib/backup)
# =============================================================================

readonly INTERVAL="${BACKUP_INTERVAL:-43200}"
readonly ID_PREFIX="${BACKUP_ID:-$(hostname)}"
readonly STATE_DIR="${BACKUP_STATE_DIR:-/var/lib/backup}"
readonly STATE_FILE="${STATE_DIR}/last_run"
readonly LOG_FILE="${STATE_DIR}/backup.log"

# ---------------------------------------------------------------------------
# Initialize state directory
# ---------------------------------------------------------------------------
init_state() {
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
  fi
  
  # Initialize log file if it doesn't exist
  if [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE"
  fi
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight() {
  local missing=()
  [[ -z "${PBS_REPOSITORY:-}" ]]  && missing+=("PBS_REPOSITORY")
  [[ -z "${PBS_PASSWORD:-}" ]]    && missing+=("PBS_PASSWORD")
  [[ -z "${PBS_FINGERPRINT:-}" ]] && missing+=("PBS_FINGERPRINT")
  [[ -z "${BACKUP_PATH:-}" ]]     && missing+=("BACKUP_PATH")

  if (( ${#missing[@]} > 0 )); then
    log "FATAL" "Missing required variables: ${missing[*]}"
    exit 1
  fi

  if [[ ! -d "$BACKUP_PATH" ]]; then
    log "FATAL" "BACKUP_PATH does not exist or is not a directory: $BACKUP_PATH"
    exit 1
  fi

  if ! command -v proxmox-backup-client &> /dev/null; then
    log "FATAL" "proxmox-backup-client not found in PATH"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Logging helper (writes to both stdout and file)
# ---------------------------------------------------------------------------
log() {
  local level="$1"; shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local message="[$timestamp] [$(printf '%-5s' "$level")] $*"
  
  printf "%s\n" "$message"
  printf "%s\n" "$message" >> "$LOG_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Check if we should run backup
# ---------------------------------------------------------------------------
should_run_backup() {
  if [[ ! -f "$STATE_FILE" ]]; then
    log "INFO" "No previous backup found. Running immediately."
    return 0
  fi

  local last_run
  last_run=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  
  local now
  now=$(date +%s)
  
  local elapsed
  elapsed=$(( now - last_run ))
  
  if [[ $elapsed -lt $INTERVAL ]]; then
    local remaining
    remaining=$(( INTERVAL - elapsed ))
    log "INFO" "Last backup: ${elapsed}s ago. Next backup in ${remaining}s."
    return 1
  fi
  
  return 0
}

# ---------------------------------------------------------------------------
# Update last run timestamp
# ---------------------------------------------------------------------------
update_last_run() {
  date +%s > "$STATE_FILE" 2>/dev/null || log "WARN" "Failed to write state file"
}

# ---------------------------------------------------------------------------
# Backup a single directory
# ---------------------------------------------------------------------------
backup_dir() {
  local dir="$1"
  local name
  name="$(basename "$dir")"
  local backup_id="${ID_PREFIX}-${name}"
  local exit_code=0

  log "INFO" "Starting backup: $name → $backup_id"

  if proxmox-backup-client backup "root.pxar:${dir}" \
       --backup-id "$backup_id" \
       --exclude '**/node_modules' \
       --exclude '**/tmp' \
       --exclude '**/.tmp' \
       --exclude '**/cache' \
       --exclude '**/.cache' \
       --exclude '**/logs' \
       --exclude '**/*.log'; then
    log "INFO" "Completed: $name ✓"
    return 0
  else
    exit_code=$?
    log "ERROR" "Failed: $name (exit code: $exit_code)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Main backup cycle
# ---------------------------------------------------------------------------
run_cycle() {
  local success=0 failure=0 total=0

  log "INFO" "========== Backup cycle started =========="
  log "INFO" "Repository: $PBS_REPOSITORY"
  log "INFO" "Backup path: $BACKUP_PATH"
  log "INFO" "ID prefix: $ID_PREFIX"

  for dir in "$BACKUP_PATH"/*/; do
    [[ -d "$dir" ]] || continue
    (( total++ )) || true

    if backup_dir "$dir"; then
      (( success++ )) || true
    else
      (( failure++ )) || true
    fi
  done

  if (( total == 0 )); then
    log "WARN" "No subdirectories found in $BACKUP_PATH"
  else
    log "INFO" "========== Cycle finished: $success/$total succeeded, $failure failed =========="
  fi
  
  # Update last run timestamp after cycle completes
  update_last_run
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
main() {
  init_state
  log "INFO" "PBS Backup container started on $(hostname)"
  log "INFO" "Interval: ${INTERVAL}s ($(( INTERVAL / 3600 ))h)"
  log "INFO" "State directory: $STATE_DIR"
  preflight

  while true; do
    if should_run_backup; then
      run_cycle
    fi
    log "INFO" "Next cycle check in 60s..."
    sleep 60
  done
}

main "$@"