# pbs-client

Docker image that runs [Proxmox Backup Client](https://pbs.proxmox.com/docs/backup-client.html) on a schedule, designed for **Docker Swarm** deployments. Automatically backs up all subdirectories under a configured path to a Proxmox Backup Server.

## Why?

Proxmox Backup Client only provides official packages for **Debian Bookworm (amd64)**. If your hosts run Debian Trixie or have ARM64 nodes (like Raspberry Pi 4), this containerized approach lets you run PBS client anywhere.

## Architecture

| Architecture | PBS Client Source | Base Image |
|---|---|---|
| `linux/amd64` | Official Proxmox APT repository (Bookworm) | `debian:12-slim` |
| `linux/arm64` | [wofferl/proxmox-backup-arm64](https://github.com/wofferl/proxmox-backup-arm64) — compiled from [official source](https://git.proxmox.com/) | `debian:12-slim` |

> The ARM64 `.deb` is **not** a fork — it's compiled directly from the official Proxmox source code via a transparent GitHub Actions pipeline.

## Quick Start

### 1. Configure credentials

```bash
cp .env.example .env
# Edit .env with your PBS server details
```

### 2. Deploy the stack

```bash
docker stack deploy -c stack.yml backup
```

## Stack Layout

The stack deploys **two services**:

| Service | Runs On | Volume Mount (env var) | Purpose |
|---|---|---|---|
| `backup-worker` | All **worker** nodes | `${BACKUP_PATH_WORKER}` | Backs up worker node data |
| `backup-manager` | The **manager** node | `${BACKUP_PATH_MANAGER}` | Backs up manager node data |

Each service backs up every subdirectory under its mounted path as a separate PBS archive, identified by `<hostname>-<dirname>`.

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PBS_REPOSITORY` | ✅ | — | PBS server connection string |
| `PBS_PASSWORD` | ✅ | — | API token secret or password |
| `PBS_FINGERPRINT` | ✅ | — | Server TLS certificate fingerprint |
| `BACKUP_PATH_WORKER` | ✅ | — | Host path to back up on worker nodes |
| `BACKUP_PATH_MANAGER` | ✅ | — | Host path to back up on manager node |
| `BACKUP_PATH` | ✅ | `/data` | Path inside container (do not change) |
| `BACKUP_INTERVAL` | ❌ | `43200` | Seconds between backup cycles (12h) |
| `BACKUP_ID` | ❌ | hostname | Prefix for backup identifiers |

## Default Exclusions

The backup script excludes common development/runtime artifacts:

- `**/node_modules`
- `**/tmp`, `**/.tmp`
- `**/cache`, `**/.cache`
- `**/logs`, `**/*.log`

## Building Locally

```bash
# AMD64
docker build --platform linux/amd64 -t pbs-client:local .

# ARM64 (requires QEMU on non-ARM hosts)
docker build --platform linux/arm64 -t pbs-client:local .
```

## Updating PBS Client Version

- **AMD64**: Automatically pulls the latest from the official Proxmox Bookworm repository at build time.
- **ARM64**: Update the `PBS_ARM64_VERSION` build arg in the Dockerfile to match the latest [wofferl release](https://github.com/wofferl/proxmox-backup-arm64/releases) for the `stable-3` (Bookworm) branch.

## Future Enhancements (Roadmap)

- **Multiple datastores support** — Configure backup targets for different PBS datastores simultaneously
- Slack/webhook notifications on backup success/failure
- Metrics export (Prometheus format)
- Backup retention policies
- Pre/post backup hooks for custom operations
