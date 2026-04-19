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
# =============================================================================

readonly INTERVAL="${BACKUP_INTERVAL:-43200}"
readonly ID_PREFIX="${BACKUP_ID:-$(hostname)}"

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
# Logging helper
# ---------------------------------------------------------------------------
log() {
  local level="$1"; shift
  printf "[%s] [%-5s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
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
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
main() {
  log "INFO" "PBS Backup container started on $(hostname)"
  log "INFO" "Interval: ${INTERVAL}s ($(( INTERVAL / 3600 ))h)"
  preflight

  while true; do
    run_cycle
    log "INFO" "Next cycle in ${INTERVAL}s..."
    sleep "$INTERVAL"
  done
}

main "$@"