# Jellyfin KOReader Sync Plugin - Installation & Usage Guide

## Quick Start

### For End Users

#### Installation via Jellyfin Plugin Catalog (Coming Soon)

1. Open Jellyfin web interface
2. Navigate to **Dashboard** → **Plugins** → **Repositories**
3. Click **Add Repository**
4. Enter:
   - **Repository Name**: `KOReader Sync`
   - **Repository URL**: `https://raw.githubusercontent.com/jakepi84/JellyfinKoReaderSync/main/manifest.json`
5. Go to **Catalog** tab
6. Find **KOReader Sync** and click **Install**
7. Restart Jellyfin

#### Manual Installation

1. Download `jellyfin-koreader-sync_1.0.0.0.zip` from [Releases](https://github.com/jakepi84/JellyfinKoReaderSync/releases)
2. Extract the ZIP file to get `Jellyfin.Plugin.KoReaderSync.dll`
3. Copy the DLL to your Jellyfin plugins folder:
   - **Linux**: `/var/lib/jellyfin/plugins/KOReader Sync/`
   - **Windows**: `%ProgramData%\Jellyfin\Server\plugins\KOReader Sync\`
   - **macOS**: `/usr/local/var/jellyfin/plugins/KOReader Sync/`
4. Restart Jellyfin server
5. Verify installation in **Dashboard** → **Plugins**

### KOReader Configuration

1. Open a book in KOReader
2. Tap the **top menu** → **Tools** → **Progress sync**
3. Configure settings:

   **Server Settings:**
   - **Server**: `http://your-jellyfin-server:8096/plugins/koreader/v1`
   
   Examples:
   - Local: `http://192.168.1.100:8096/plugins/koreader/v1`
   - Remote: `https://jellyfin.example.com/plugins/koreader/v1`

   **Authentication:**
   - **Username**: Your Jellyfin username
   - **Password**: Your Jellyfin password

   **Sync Options:**
   - Enable **auto sync**
   - Set sync method to **on page turn** or **on book close**
   - **IMPORTANT**: Set **document matching method** to **Filename**

4. Tap **Login** to test the connection
5. Success message should appear: "Logged in successfully"

### Verification

1. Open any book in KOReader
2. Read a few pages
3. Check sync status in KOReader (should show "Last sync: just now")
4. Open the same book on another device
5. Progress should sync automatically

## Troubleshooting

### Connection Issues

**Symptom**: "Connection failed" in KOReader

**Solutions**:
- ✅ Verify the server URL includes `/plugins/koreader/v1`
- ✅ Check Jellyfin is accessible from your device
- ✅ Test the healthcheck: `curl http://your-server:8096/plugins/koreader/v1/healthcheck`
- ✅ Ensure the plugin is installed (check Jellyfin Dashboard → Plugins)
- ✅ Check firewall settings

### Authentication Issues

**Symptom**: "Authentication failed"

**Solutions**:
- ✅ Verify username and password are correct
- ✅ Check your user account exists in Jellyfin
- ✅ Try logging in to Jellyfin web interface first
- ✅ Check Jellyfin logs: Dashboard → Logs

### Sync Not Working

**Symptom**: Progress not syncing between devices

**Solutions**:
- ✅ Verify both devices use the same server URL
- ✅ Check both devices are authenticated with same user
- ✅ Enable auto sync in KOReader settings
- ✅ Manually trigger sync by closing/reopening book
- ✅ Check Jellyfin logs for errors

### Plugin Not Loading

**Symptom**: Plugin doesn't appear in Jellyfin

**Solutions**:
- ✅ Verify DLL is in the correct folder
- ✅ Folder name must be exactly: `KOReader Sync/`
- ✅ Restart Jellyfin completely (not just reload)
- ✅ Check Jellyfin logs for plugin loading errors
- ✅ Verify Jellyfin version is 10.10.0 or higher

## Advanced Usage

### Testing with curl

```bash
# Set your credentials
USERNAME="admin"
PASSWORD="yourpassword"
SERVER="http://localhost:8096"
PASSWORD_MD5=$(echo -n "$PASSWORD" | md5sum | cut -d' ' -f1)

# Test health check
curl "$SERVER/plugins/koreader/v1/healthcheck"

# Test authentication
curl -X GET \
  -H "x-auth-user: $USERNAME" \
  -H "x-auth-key: $PASSWORD_MD5" \
  "$SERVER/plugins/koreader/v1/users/auth"

# Update progress
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "x-auth-user: $USERNAME" \
  -H "x-auth-key: $PASSWORD_MD5" \
  -d '{
    "document": "test123",
    "percentage": 0.5,
    "progress": "/body/p[1]",
    "device": "TestDevice"
  }' \
  "$SERVER/plugins/koreader/v1/syncs/progress"

# Get progress
curl -X GET \
  -H "x-auth-user: $USERNAME" \
  -H "x-auth-key: $PASSWORD_MD5" \
  "$SERVER/plugins/koreader/v1/syncs/progress/test123"
```

### Data Location

Progress data is stored at:
```
<jellyfin-data-path>/koreader-sync/<user-id>/<document-hash>.json
```

Example:
```
/var/lib/jellyfin/data/koreader-sync/550e8400-e29b-41d4-a716-446655440000/abc123def456.json
```

Each file contains:
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

### Backup

To backup your sync data:
```bash
# On Linux
cp -r /var/lib/jellyfin/data/koreader-sync ~/koreader-sync-backup

# On Windows
xcopy "%ProgramData%\Jellyfin\Server\data\koreader-sync" "C:\backup\koreader-sync" /E /I
```

## Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/jakepi84/JellyfinKoReaderSync.git
cd JellyfinKoReaderSync

# Build using the package script
chmod +x package.sh
./package.sh 1.0.0.0

# Or build manually
dotnet build --configuration Release -p:TreatWarningsAsErrors=false

# Output: Jellyfin.Plugin.KoReaderSync/bin/Release/net9.0/Jellyfin.Plugin.KoReaderSync.dll
```

### Project Structure

```
JellyfinKoReaderSync/
├── Jellyfin.Plugin.KoReaderSync/
│   ├── Configuration/           # Plugin configuration
│   ├── Models/                  # Data transfer objects
│   ├── Services/                # Business logic
│   ├── KoReaderSyncApi.cs      # API controller
│   ├── KoReaderSyncPlugin.cs   # Plugin entry point
│   └── PluginServiceRegistrator.cs
├── .github/workflows/           # CI/CD automation
├── API.md                       # API documentation
├── CHANGELOG.md                 # Version history
├── README.md                    # Main documentation
├── build.yaml                   # Plugin manifest
├── manifest.json                # Jellyfin catalog manifest
└── package.sh                   # Build script
```

## Support

- **Issues**: [GitHub Issues](https://github.com/jakepi84/JellyfinKoReaderSync/issues)
- **Documentation**: [README](README.md) | [API Docs](API.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)

## Contributing

Contributions are welcome! Areas for contribution:
- Additional book matching strategies (metadata, alternative identifiers)
- Jellyfin UI integration
- Additional authentication methods
- Unit tests
- Documentation improvements

See [Contributing Guidelines](README.md#contributing) for details.

## License

MIT License - See [LICENSE](LICENSE) for details.

---

**Version**: 1.0.0  
**Last Updated**: 2024-12-23  
**Jellyfin Compatibility**: 10.10.0+  
**KOReader Compatibility**: All versions with Progress Sync
