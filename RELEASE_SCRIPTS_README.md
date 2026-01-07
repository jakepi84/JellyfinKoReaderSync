# Generic Jellyfin Plugin Release Scripts

These scripts automate building, packaging, and releasing Jellyfin plugins to GitHub using GitHub CLI.

## Overview

- **`release.ps1`** – High-level orchestrator. Calls `build-release.ps1` with GitHub CLI enabled.
- **`build-release.ps1`** – Builds, packages, updates manifest, and uploads to GitHub.
- **`update-manifest.ps1`** – Updates `manifest.json` with version, checksum, and download URL.

## Features

- **Auto-detection** of plugin name and repository slug from git remote
- **GitHub CLI (`gh`)** integration for creating/updating releases
- **Optional auto-tagging** with `-AutoTag` flag
- **Manifest auto-update** with checksums and source URLs
- **Generic across all Jellyfin plugins** – no hardcoding needed

## Prerequisites

1. **GitHub CLI** installed:
   ```powershell
   winget install GitHub.cli
   ```
   Or download from https://cli.github.com/

2. **GitHub CLI authenticated**:
   ```powershell
   gh auth login
   ```

3. **Git repository** with a valid remote origin pointing to GitHub

4. **Project structure**:
   ```
   YourRepo/
   ├── release.ps1
   ├── build-release.ps1
   ├── update-manifest.ps1
   ├── manifest.json
   └── Jellyfin.Plugin.YourPlugin/
       ├── Jellyfin.Plugin.YourPlugin.csproj
       └── bin/Release/net9.0/Jellyfin.Plugin.YourPlugin.dll
   ```

## Usage

### Simple Release (Auto-detect everything)

```powershell
.\release.ps1
```

This will:
1. Auto-detect your plugin name (e.g., `Jellyfin.Plugin.KoReaderSync`)
2. Auto-detect your GitHub repo slug from git remote (e.g., `jakepi84/JellyfinKoReaderSync`)
3. Use the latest git tag as the version
4. Build, package, update manifest, and create/update GitHub release

### Specify Version & Tag

```powershell
.\release.ps1 -Version 3.0.0.0 -ReleaseTag v3.0.0
```

### Auto-Tag (Create and push tag if missing)

```powershell
.\release.ps1 -AutoTag
```

This will automatically create and push the tag to origin before releasing.

### With Explicit Plugin Name & Repo

```powershell
.\release.ps1 -PluginName Jellyfin.Plugin.MyPlugin -RepositorySlug username/JellyfinMyPlugin
```

## Script Parameters

### `release.ps1`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Version` | string | (auto-detect) | Semantic version (e.g., `2.0.0.0`) |
| `ReleaseTag` | string | (auto-detect) | Git tag (e.g., `v2.0.0`) |
| `PluginName` | string | (auto-detect) | Full plugin name (e.g., `Jellyfin.Plugin.KoReaderSync`) |
| `RepositorySlug` | string | (auto-detect) | GitHub repo (e.g., `jakepi84/JellyfinKoReaderSync`) |
| `AutoTag` | switch | false | Auto-create and push git tag if missing |

### `build-release.ps1`

All parameters from `release.ps1`, plus:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `CreateGitHubRelease` | switch | true | Always create/update GitHub release with `gh` CLI |

### `update-manifest.ps1`

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Version` | string | (required) | Semantic version |
| `ZipPath` | string | (required) | Path to ZIP file |
| `ReleaseTag` | string | (auto-detect) | Git tag |
| `RepositorySlug` | string | (auto-detect) | GitHub repo slug |

## How It Works

1. **Auto-Detection**:
   - Plugin name: Looks for `Jellyfin.Plugin.*` folder
   - Repository slug: Parses git remote URL to extract `owner/repo`

2. **Build & Package**:
   - Runs `dotnet build` and `dotnet restore`
   - Copies DLL to `artifacts/jellyfin-{plugin-name}`
   - Creates ZIP: `artifacts/jellyfin-{plugin-name}_{version}.zip`

3. **Manifest Update**:
   - Calculates MD5 checksum of ZIP
   - Extracts target ABI from `build.yaml` or uses default (10.10.0.0)
   - Updates `manifest.json` with version, checksum, source URL, and timestamp

4. **GitHub Release**:
   - Creates/updates release tag
   - Uses `gh release create` or `gh release upload` (GitHub CLI)
   - Automatically populates release title and notes from commit message

## Example Workflows

### New Release from Latest Tag

```powershell
# Assuming you have a v2.0.0 tag in git
git tag v2.0.0
git push origin v2.0.0
.\release.ps1
```

### Release with New Tag (Auto-create)

```powershell
# Let the script create the tag
.\release.ps1 -AutoTag
```

### Release Across Multiple Plugins

Copy the three scripts to each plugin repository. They auto-detect everything:

```powershell
# In plugin-1 repo
.\release.ps1

# In plugin-2 repo
.\release.ps1

# All auto-configured!
```

## Troubleshooting

### "GitHub CLI 'gh' not found"
Install via: `winget install GitHub.cli`

### "Local tag not found"
Either:
- Create manually: `git tag v2.0.0 && git push origin v2.0.0`
- Or use: `.\release.ps1 -AutoTag`

### "Could not infer PluginName"
Ensure your plugin folder is named `Jellyfin.Plugin.*` (e.g., `Jellyfin.Plugin.MyPlugin`)

### "Could not infer RepositorySlug"
Ensure git remote is set: `git config --get remote.origin.url`

### Build warnings
These don't prevent packaging. Code analysis warnings (CA1848, CA1031, etc.) are benign.

## Customization

### Change target framework
Edit `build-release.ps1` line where `$targetFramework = "net9.0"` is set.

### Change default target ABI
Edit `update-manifest.ps1` default fallback in the manifest update section.

### Change ZIP artifact naming
The naming is automatic: `jellyfin-{plugin-name}_{version}.zip`
- Plugin name is derived from folder: `Jellyfin.Plugin.KoReaderSync` → `jellyfin-koreader-sync`

## Notes

- **GitHub CLI is always used** for release management (no REST token needed)
- **Manifest is auto-validated** to avoid duplicate versions
- **Remote tags are required** before GitHub release creation
- **Commit message** is automatically included in release notes

---

For questions or contributions, refer to your plugin's README.
