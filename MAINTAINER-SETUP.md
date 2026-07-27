# Jellyfin KOReader Sync Plugin - Maintainer Setup

## Overview
This document describes the automated monthly maintenance system for the Jellyfin KOReader Sync plugin.

## Goal
Automatically check for new Jellyfin releases on the 15th of each month and update the plugin's targetABI if needed.

## Architecture

### Cron Job
- **Job ID**: `4e8a4713-9711-4692-a37f-fa15cc3d6b22`
- **Schedule**: 15th of every month at 9:00 AM CDT
- **Model**: `ollama/qwen3.5:cloud`
- **Timeout**: 30 minutes (1800 seconds)
- **Delivery**: Discord DM to user `156804918412443648`

### Maintenance Script
**Location**: `/home/jake/.openclaw/workspace/scripts/jellyfin-plugin-maintenance.py`

**What it does:**
1. Fetches latest Jellyfin release from GitHub
2. Compares Jellyfin version against current `targetABI` in `manifest.json`
3. If ABI update needed:
   - Fetches changelog for breaking changes
   - Sets up Docker test environment with Jellyfin
   - Runs regression tests using EPUBs from `/home/jake/.openclaw/workspace/dev/epubs/`
   - Updates `targetABI` in manifest
   - Builds and releases new plugin version
   - Commits changes to git
4. Saves state to `memory/jellyfin-sync-state.json`
5. Sends Discord summary

### State File
**Location**: `/home/jake/.openclaw/workspace/memory/jellyfin-sync-state.json`

Tracks:
- Last check timestamp
- Last Jellyfin version checked
- Current target ABI
- Last released plugin version
- Last action taken

### Test Resources
- **EPUBs**: `/home/jake/.openclaw/workspace/dev/epubs/` (James S.A. Corey collection)
- **Docker**: Spins up temporary `jellyfin/jellyfin:latest` container for testing
- **Plugin repo**: `/home/jake/.openclaw/workspace/JellyfinKoReaderSync/`

## Version Comparison Logic

Jellyfin versions follow semantic versioning: `MAJOR.MINOR.PATCH`
Plugin targetABI format: `MAJOR.MINOR.0.0`

Example:
- Jellyfin 10.11.11 → requires ABI 10.11.0.0
- Plugin targetABI 10.11.0.0 → compatible ✓
- Plugin targetABI 10.10.0.0 → needs update to 10.11.0.0

## Manual Testing

Run the maintenance script manually:
```bash
cd /home/jake/.openclaw/workspace
python3 scripts/jellyfin-plugin-maintenance.py
```

## Build & Release Process

The script uses `build-release.sh` which:
1. Reads version from git tags
2. Builds .NET plugin DLL
3. Creates ZIP archive
4. Creates GitHub release
5. Updates `manifest.json` with checksum and download URL

## Discord Notifications

Monthly summaries include:
- Latest Jellyfin version
- Current target ABI
- Whether update was needed
- Test results
- Release status (if applicable)

## Troubleshooting

### Script fails to fetch Jellyfin release
Check GitHub CLI authentication: `gh auth status`

### Docker container won't start
Check Docker daemon: `systemctl status docker`
Clean up stale containers: `docker container prune -f`

### Build fails
Check .NET SDK: `dotnet --version`
Restore dependencies: `cd JellyfinKoReaderSync && dotnet restore`

### Manifest not updating
Ensure git credentials are configured: `gh auth login`

## Next Scheduled Run
August 15, 2026 at 9:00 AM CDT

---
*Setup completed: July 27, 2026*
