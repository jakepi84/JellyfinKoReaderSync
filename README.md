# Jellyfin KOReader Sync Plugin

A Jellyfin plugin that enables seamless reading progress synchronization between [KOReader](https://github.com/koreader/koreader) devices and your Jellyfin server. Keep your book reading progress in sync across all your e-readers and devices!

## Features

- ✅ **KOReader Progress Sync API Compatible**: Implements the KOReader sync server API specification
- ✅ **Jellyfin Native Authentication**: Uses your existing Jellyfin username and password
- ✅ **Automatic Conflict Resolution**: Keeps the furthest reading progress when conflicts occur
- ✅ **Smart Book Matching**: Uses KOReader's partial MD5 algorithm (samples at exponential intervals)
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
- **Document matching method**: Leave as **Binary** (default) for best compatibility

### Important Notes

⚠️ **Document Matching Method:**
- **Use KOReader's default "Binary" method** - fully supported and recommended!
- Binary method uses partial MD5 algorithm that samples file at exponential intervals (256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 1GB)
- This is the most reliable method - path-independent and works even if files are renamed
- Progress will always sync between KOReader devices regardless of matching
- Matching with Jellyfin determines whether progress appears in the Jellyfin UI
- For troubleshooting matching issues, see [TROUBLESHOOTING-MATCHING.md](TROUBLESHOOTING-MATCHING.md)

⚠️ **Authentication Requirements:**
- The plugin requires KOReader custom headers (`x-auth-user`, `x-auth-key`)
- KOReader sends the MD5 hash of your password in the `x-auth-key` header
- HTTP Basic Authentication is **optional** but provides enhanced security
- Your Jellyfin username must match the `x-auth-user` header value
- Make sure to enter your credentials exactly as they appear in Jellyfin

⚠️ **Security Considerations:**
- **Standard Mode** (headers only): Validates username existence but not the password hash. **⚠️ WARNING: Anyone who can send HTTP requests to your server and knows a valid Jellyfin username can access that user's reading progress data.** Only use in trusted network environments (e.g., home LAN behind firewall) or with additional authentication at the network level.
- **Enhanced Security Mode** (headers + Basic auth): Validates password against Jellyfin for stronger authentication. **✅ RECOMMENDED for internet-facing servers.**
- Reading progress data is considered low-sensitivity (book position, percentage)

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

1. **Custom Headers** (KOReader format) - **Required**:
   - `x-auth-user`: Your Jellyfin username
   - `x-auth-key`: MD5 hash of your Jellyfin password

2. **HTTP Basic Authentication** - **Optional** (for enhanced security):
   - `Authorization: Basic <base64(username:password)>`

### Example API Call

```bash
# Get reading progress for a document (using KOReader headers only)
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 5f4dcc3b5aa765d61d8327deb882cf99" \
  https://jellyfin.example.com/plugins/koreader/v1/syncs/progress/abc123def456
```

## Book Matching

The plugin uses KOReader's exact matching algorithm to identify books between KOReader and Jellyfin.

### Binary Method (Default - Fully Supported)

KOReader's default "Binary" method uses a sophisticated partial MD5 algorithm that samples file at exponential intervals. This is the **most reliable** method because:

- ✅ **Path-independent**: Works regardless of where the file is located
- ✅ **Filename-independent**: Matches books even if renamed or moved
- ✅ **Efficient**: Samples at strategic positions instead of hashing entire file
- ✅ **Consistent**: Same algorithm across all devices
- ✅ **No configuration needed**: Works with KOReader defaults

#### How It Works

The partial MD5 algorithm samples 1KB chunks from these positions in the file:
- 256 bytes
- 1 KB
- 4 KB  
- 16 KB
- 64 KB
- 256 KB
- 1 MB
- 4 MB
- 16 MB
- 64 MB
- 1 GB (for very large files)

These samples are concatenated and hashed to create a unique identifier that's:
- Fast to calculate (only reads ~11KB for most books)
- Robust against minor file changes
- Reliable across different file systems and devices

The plugin uses the **exact same algorithm** as KOReader, ensuring perfect compatibility.

### Matching Process

1. **KOReader** calculates the binary hash when you open a book
2. **Plugin** calculates the same binary hash for all books in your Jellyfin library
3. **Match** is made when hashes are identical
4. **Progress** syncs to Jellyfin UI and all connected devices

### Matching Results

When a book is successfully matched:
- ✅ Progress is visible in the Jellyfin UI
- ✅ Books marked as "In Progress" or "Finished" based on reading percentage
- ✅ Last played date is updated
- ✅ Works seamlessly with OPDS plugin downloads

When a book cannot be matched:
- ⚠️ Progress is still stored and synced between KOReader devices
- ⚠️ Progress won't be visible in the Jellyfin UI
- 💡 Most common cause: Different file versions or editions
- 📖 See [TROUBLESHOOTING-MATCHING.md](TROUBLESHOOTING-MATCHING.md) for detailed diagnostics

### Important: File Versions Matter

Since the binary hash is based on file content, the **exact same file** must be in both locations:
- ✅ Same EPUB file copied from Jellyfin to KOReader works perfectly
- ✅ Books downloaded via OPDS plugin match automatically
- ❌ Different editions (even with same title/author) won't match
- ❌ Re-encoded or modified files won't match
- ❌ Files from different sources may differ slightly

**Tip**: For best results, use the Jellyfin OPDS plugin to download books directly to KOReader.

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

Progress data is stored under Jellyfin's plugin configuration directory (writable across OSes):
```
<plugin-config-path>/KoReaderSync/<user-id>/<document-hash>.json
```
Common locations:
- Linux (Docker): `/config/plugins/KoReaderSync`
- Linux (package): `/var/lib/jellyfin/plugins/KoReaderSync`
- Windows: `%ProgramData%\Jellyfin\Server\plugins\KoReaderSync`

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
- **Recommended**: Use KOReader's default "Binary" document matching method.
- The plugin uses KOReader's exact partial MD5 algorithm for matching
- Ensure the **exact same file** is in both Jellyfin and KOReader:
  - ✅ Use OPDS plugin to download from Jellyfin directly
  - ✅ Copy the same file to both locations
  - ❌ Different editions or file versions won't match
- Check file integrity: Compare file sizes and MD5 checksums
- Ensure books in Jellyfin are accessible (not corrupted or missing)
- Check Jellyfin logs for matching attempts and any errors
- Progress is always synced between KOReader devices, even if Jellyfin matching fails
- **For detailed troubleshooting:** See [TROUBLESHOOTING-MATCHING.md](TROUBLESHOOTING-MATCHING.md)

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

- Enhanced diagnostics and logging for matching issues
- Performance optimizations for large libraries
- Web-based configuration UI
- Support for additional e-reader sync protocols
- Unit tests and integration tests
- Documentation improvements
- Support for audiobook progress tracking

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

---

**Made with copilot, I am not a developer and this is mostly AI slop code.**