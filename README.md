# Jellyfin KOReader Sync Plugin

A Jellyfin plugin that enables seamless reading progress synchronization between [KOReader](https://github.com/koreader/koreader) devices and your Jellyfin server. Keep your book reading progress in sync across all your e-readers and devices!

## Features

- ✅ **KOReader Progress Sync API Compatible**: Implements the KOReader sync server API specification
- ✅ **Jellyfin Native Authentication**: Uses your existing Jellyfin username and password
- ✅ **Automatic Conflict Resolution**: Keeps the furthest reading progress when conflicts occur
- ✅ **Book Matching by ISBN**: Attempts to match books between KOReader and Jellyfin using ISBN metadata
- ✅ **Multi-Device Support**: Sync progress across multiple KOReader devices
- ✅ **Privacy Focused**: Stores only progress data (percentage, position), no file content

## How It Works

1. **KOReader** sends reading progress updates to the plugin endpoint
2. **Plugin** authenticates using your Jellyfin credentials
3. **Progress** is stored and synchronized across all your devices
4. **Conflicts** are automatically resolved by keeping the furthest reading position
5. **Jellyfin UI** can optionally display your reading progress (when books are matched)

## Installation

### From Jellyfin Plugin Catalog (Recommended)

1. Open Jellyfin and navigate to **Dashboard** → **Plugins** → **Repositories**
2. Add a new repository:
   - **Repository Name**: `KOReader Sync`
   - **Repository URL**: `https://raw.githubusercontent.com/jakepi84/JellyfinKoReaderSync/main/manifest.json`
3. Go to **Catalog** tab and find **KOReader Sync**
4. Click **Install**
5. Restart Jellyfin

### Manual Installation

1. Download the latest `Jellyfin.Plugin.KoReaderSync.dll` from [Releases](https://github.com/jakepi84/JellyfinKoReaderSync/releases)
2. Place it in your Jellyfin plugins folder:
   - **Linux**: `/var/lib/jellyfin/plugins/KOReader Sync/`
   - **Windows**: `%ProgramData%\Jellyfin\Server\plugins\KOReader Sync\`
   - **macOS**: `/usr/local/var/jellyfin/plugins/KOReader Sync/`
3. Restart Jellyfin

## KOReader Configuration

### Step-by-Step Setup

1. **Open KOReader** on your device
2. Tap the **top menu** → **Tools** → **Progress sync**
3. Configure the following settings:

#### Sync Server Settings

- **Server**: Enter your Jellyfin server URL with the plugin path:
  ```
  https://your-jellyfin-server.com/plugins/koreader/v1
  ```
  
  **Examples:**
  - Local network: `http://192.168.1.100:8096/plugins/koreader/v1`
  - Remote server: `https://jellyfin.example.com/plugins/koreader/v1`
  - With subdirectory: `https://example.com/jellyfin/plugins/koreader/v1`

#### Authentication Settings

- **Username**: Your Jellyfin username
- **Password**: Your Jellyfin password

#### Sync Settings

- **Enable sync**: Toggle ON
- **Sync method**: Select **on page turn** or **on book close** (recommended)
- **Prompt before syncing**: Optional (your preference)

### Important Notes

⚠️ **Authentication Requirements:**
- The plugin requires **both** the KOReader custom headers (`x-auth-user`, `x-auth-key`) **and** HTTP Basic Authentication
- KOReader sends the MD5 hash of your password in the `x-auth-key` header
- Basic Authentication is used to authenticate with Jellyfin's user manager
- Make sure to enter your credentials exactly as they appear in Jellyfin

⚠️ **HTTPS Recommendations:**
- Use HTTPS when accessing Jellyfin over the internet
- For local network access, HTTP is acceptable
- If using a self-signed certificate, you may need to accept it in KOReader

### Testing the Connection

1. In KOReader's Progress Sync settings, tap **Login**
2. You should see a success message: "Logged in successfully"
3. Open any book and read a few pages
4. Check the sync status - it should show "Last sync: just now"

## API Endpoints

The plugin implements the following KOReader-compatible endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/plugins/koreader/v1/healthcheck` | GET | Health check endpoint |
| `/plugins/koreader/v1/users/auth` | GET | Authenticate user credentials |
| `/plugins/koreader/v1/syncs/progress/:document` | GET | Get reading progress for a document |
| `/plugins/koreader/v1/syncs/progress` | PUT | Update reading progress for a document |

### Authentication

All endpoints (except `/healthcheck`) require authentication via:

1. **Custom Headers** (KOReader format):
   - `x-auth-user`: Your Jellyfin username
   - `x-auth-key`: MD5 hash of your Jellyfin password

2. **HTTP Basic Authentication** (required for Jellyfin authentication):
   - `Authorization: Basic <base64(username:password)>`

### Example API Call

```bash
# Get reading progress for a document
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 5f4dcc3b5aa765d61d8327deb882cf99" \
  -u myusername:mypassword \
  https://jellyfin.example.com/plugins/koreader/v1/syncs/progress/abc123def456
```

## Book Matching

The plugin attempts to match books between KOReader and Jellyfin using:

1. **ISBN** - Primary method (most reliable)
2. **File hash** - Future enhancement
3. **Metadata matching** - Future enhancement

When a book is successfully matched:
- Progress is visible in the Jellyfin UI
- Books marked as "In Progress" or "Finished" based on reading percentage
- Last played date is updated

When a book cannot be matched:
- Progress is still stored and synced between KOReader devices
- Progress won't be visible in the Jellyfin UI

## Conflict Resolution

When the same book is read on multiple devices:
- The plugin compares progress percentages
- **The furthest progress wins**
- Both devices will sync to the furthest position
- Timestamp is updated to reflect the latest sync

**Example:**
- Device A: 45% complete
- Device B: 60% complete
- Result: Both devices sync to 60%

## Data Storage

Progress data is stored in your Jellyfin data directory:
```
<jellyfin-data-path>/koreader-sync/<user-id>/<document-hash>.json
```

Each progress file contains:
```json
{
  "Document": "abc123def456",
  "Percentage": 0.45,
  "Progress": "/body/DocFragment[20]/body/p[22]/img.0",
  "Device": "PocketBook",
  "DeviceId": "550e8400-e29b-41d4-a716-446655440000",
  "Timestamp": 1703289600
}
```

## Troubleshooting

### Connection Issues

**Problem**: KOReader shows "Connection failed"

**Solutions:**
- Verify the server URL is correct (include `/plugins/koreader/v1`)
- Check that Jellyfin is accessible from your device
- Ensure the plugin is installed and Jellyfin has been restarted
- Test the healthcheck endpoint: `https://your-server/plugins/koreader/v1/healthcheck`

### Authentication Issues

**Problem**: "Authentication failed" error

**Solutions:**
- Verify your Jellyfin username and password are correct
- Check that your user account has appropriate permissions
- Ensure you're using the correct credentials (not an API key)
- Check Jellyfin logs for authentication errors

### Sync Not Working

**Problem**: Progress not syncing between devices

**Solutions:**
- Verify both devices are configured with the same server and credentials
- Check that automatic sync is enabled in KOReader settings
- Manually trigger a sync by closing and reopening the book
- Check Jellyfin logs for errors: Dashboard → Logs

### Progress Not Showing in Jellyfin

**Problem**: Reading progress not visible in Jellyfin UI

**Solutions:**
- This is expected if the book cannot be matched by ISBN
- Verify your book files have ISBN metadata
- Progress is still synced between KOReader devices even without Jellyfin UI visibility
- Future versions may support additional matching methods

## Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/jakepi84/JellyfinKoReaderSync.git
cd JellyfinKoReaderSync

# Restore dependencies
dotnet restore

# Build the plugin
dotnet build --configuration Release

# Or use the package script (automatically extracts version from Directory.Build.props)
./package.sh

# Output will be in:
# Jellyfin.Plugin.KoReaderSync/bin/Release/net9.0/Jellyfin.Plugin.KoReaderSync.dll
# release/jellyfin-koreader-sync_<version>.zip (if using package.sh)
```

### Versioning

The plugin version is managed in `Directory.Build.props`. When you update the version:

1. Edit `Directory.Build.props` and change the `<Version>` value
2. Commit and push to the main branch
3. The GitHub Actions workflow will automatically:
   - Build the plugin with the new version
   - Create a release zip file
   - Update `manifest.json` with the new version, checksum, and download URL
   - Create a GitHub release

The `manifest.json` is automatically maintained by the build workflow and should not be manually edited for version information.

### Project Structure

```
JellyfinKoReaderSync/
├── Jellyfin.Plugin.KoReaderSync/
│   ├── Configuration/           # Plugin configuration
│   ├── Models/                  # Data transfer objects
│   ├── Services/                # Business logic and sync management
│   ├── KoReaderSyncApi.cs      # API controller
│   ├── KoReaderSyncPlugin.cs   # Plugin entry point
│   └── PluginServiceRegistrator.cs  # Dependency injection
├── build.yaml                   # Plugin manifest
└── README.md                    # This file
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Areas for Contribution

- Additional book matching strategies (file hash, metadata)
- Enhanced conflict resolution options
- Web-based configuration UI
- Support for additional e-reader sync protocols
- Unit tests and integration tests
- Documentation improvements

## Privacy & Security

- **No file content** is stored or transmitted
- Only reading progress data (position, percentage) is synced
- Authentication uses Jellyfin's existing user management
- All data is stored locally on your Jellyfin server
- HTTPS is recommended for remote access

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Jellyfin](https://jellyfin.org/) - The free software media system
- [KOReader](https://koreader.rocks/) - An ebook reader application
- [KOReader Sync Server](https://github.com/koreader/koreader-sync-server) - Reference implementation

## Support

- **Issues**: [GitHub Issues](https://github.com/jakepi84/JellyfinKoReaderSync/issues)
- **Discussions**: [GitHub Discussions](https://github.com/jakepi84/JellyfinKoReaderSync/discussions)
- **Jellyfin Community**: [Jellyfin Forum](https://forum.jellyfin.org/)

---

Made with copilot, I am not a developer and this is mostly AI slop code.