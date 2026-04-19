ARG TARGETARCH

# =============================================================================
# Stage: AMD64 runtime — Official Proxmox PBS client repository (Bookworm)
# =============================================================================
FROM debian:12-slim AS runtime-amd64

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl ca-certificates gnupg && \
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
      -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg && \
    echo "deb http://download.proxmox.com/debian/pbs-client bookworm main" \
      > /etc/apt/sources.list.d/pbs-client.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends proxmox-backup-client && \
    apt-get purge -y --auto-remove curl gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Stage: ARM64 runtime — Community-compiled .deb from official Proxmox source
#
# Proxmox does NOT publish official ARM64 packages. This stage downloads a
# .deb compiled from git.proxmox.com by the wofferl/proxmox-backup-arm64
# project (transparent CI on GitHub Actions). The version is pinned.
# =============================================================================
FROM debian:12-slim AS runtime-arm64

ARG PBS_ARM64_VERSION=3.4.8-3

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -fsSL \
      "https://github.com/wofferl/proxmox-backup-arm64/releases/download/${PBS_ARM64_VERSION}/proxmox-backup-client_${PBS_ARM64_VERSION}_arm64.deb" \
      -o /tmp/pbs-client.deb && \
    dpkg -i /tmp/pbs-client.deb || true && \
    apt-get install -fy --no-install-recommends && \
    rm -f /tmp/pbs-client.deb && \
    apt-get purge -y --auto-remove curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Stage: Final image (selected by TARGETARCH at build time)
# =============================================================================
FROM runtime-${TARGETARCH}

LABEL org.opencontainers.image.title="pbs-backup" \
      org.opencontainers.image.description="Proxmox Backup Client for automated Docker Swarm backups" \
      org.opencontainers.image.source="https://github.com/mrcsmcl/pbs-client" \
      org.opencontainers.image.licenses="AGPL-3.0"

COPY backup.sh /usr/local/bin/backup.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/healthcheck.sh

HEALTHCHECK --interval=300s --timeout=10s --start-period=30s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/backup.sh"]