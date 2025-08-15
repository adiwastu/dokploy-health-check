# Dokploy Doktor

Automated troubleshooting tool for self-hosted Dokploy instances. Diagnoses and fixes common UI accessibility issues.

## Quick Start

```bash
# Download and run
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/dokploy-recovery/main/dokploy-doctor.sh -o dokploy-doctor.sh
chmod +x dokploy-doctor.sh
./dokploy-doctor.sh
```

## What It Fixes

- Low disk space causing database recovery mode
- Container race conditions during startup/restart  
- Database connection failures (ENOTFOUND dokploy-postgres)
- Traefik configuration errors and routing issues
- Service scaling problems and unhealthy containers

## Usage

### Full automated recovery (default)
```bash
./dokploy-doctor.sh
```

### Check problems without fixing
```bash
./dokploy-doctor.sh --check-only
```

### Interactive mode
```bash
./dokploy-doctor.sh --interactive
```

### Docker cleanup only
```bash
./dokploy-doctor.sh --cleanup
```

## How It Works

1. **Validates environment** - Checks Docker and disk space
2. **Monitors containers** - dokploy, postgres, redis, traefik
3. **Analyzes logs** - Detects common error patterns
4. **Applies fixes** - Service restarts, cleanups, configuration repairs
5. **Verifies access** - Tests UI on http://localhost:3000

## Sample Output

```bash
=================================
  Dokploy Health Check & Recovery
=================================

>>> Checking Docker availability...
✓ Docker is available
>>> Checking container status...
✗ dokploy-traefik service is not healthy (0/1)
>>> Fixing Traefik configuration...
✓ Traefik restarted
>>> Final verification...
✓ Dokploy UI is accessible on http://localhost:3000
```

## If It Still Doesn't Work

Check individual container logs:
```bash
docker service logs dokploy
docker service logs dokploy-postgres  
docker logs dokploy-traefik
```

Try different URLs:
- http://localhost:3000
- http://YOUR_SERVER_IP:3000

Based on troubleshooting steps from the [official Dokploy documentation](https://dokploy.com/docs/troubleshooting).
