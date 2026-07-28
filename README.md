# Jellyfin KOReader Sync

A Jellyfin plugin that syncs reading progress between [KOReader](https://github.com/koreader/koreader) and your Jellyfin server. Keep your place across all your e-readers.

## 🤖 Maintained by AI

This plugin is maintained by an automated AI assistant with monthly checks for Jellyfin compatibility, full regression testing, and end-to-end sync validation — all under Jake's supervision. The AI handles the grunt work; Jake's still the human in charge.

## Features

- **KOReader Sync API compatible** — implements the [KOReader sync server](https://github.com/koreader/koreader-sync-server) spec
- **Jellyfin native auth** — uses your existing Jellyfin username and password
- **Conflict resolution** — keeps the furthest reading progress when devices disagree
- **Binary book matching** — uses KOReader's partial MD5 algorithm for path-independent identification
- **Multi-device sync** — progress follows you across every KOReader device
- **Privacy focused** — stores only position and percentage, never file content

## Installation

### From Plugin Catalog

1. Go to **Dashboard → Plugins → Repositories** in Jellyfin
2. Add repository:
   - **Name**: `KOReader Sync`
   - **URL**: `https://raw.githubusercontent.com/jakepi84/JellyfinKoReaderSync/main/manifest.json`
3. Go to **Catalog** tab, find **KOReader Sync**, click **Install**
4. Restart Jellyfin

### Manual

1. Download `Jellyfin.Plugin.KoReaderSync.dll` from [Releases](https://github.com/jakepi84/JellyfinKoReaderSync/releases)
2. Place it in your plugins folder:
   - **Linux**: `/var/lib/jellyfin/plugins/KOReader Sync/`
   - **Windows**: `%ProgramData%\Jellyfin\Server\plugins\KOReader Sync\`
   - **Docker**: `/config/plugins/KOReader Sync/`
3. Restart Jellyfin

## KOReader Setup

1. Open KOReader → **top menu** → **Tools** → **Progress sync**
2. Set **Server** to your Jellyfin URL with the plugin path:
   ```
   http://192.168.1.100:8096/plugins/koreader/v1
   ```
   For remote access, use HTTPS: `https://jellyfin.example.com/plugins/koreader/v1`
3. Enter your **Jellyfin username** and **password**
4. Enable sync and choose trigger (**on page turn** or **on book close**)
5. Leave document matching as **Binary** (default)
6. Tap **Login** — you should see "Logged in successfully"

### Authentication

KOReader sends credentials as custom headers:
- `x-auth-user`: your Jellyfin username
- `x-auth-key`: MD5 hash of your Jellyfin password

HTTP Basic Auth is optional but recommended for internet-facing servers — it validates the password against Jellyfin for stronger security. Without it, anyone who can reach your server and knows a valid username can read that user's progress data. Use HTTPS regardless.

### Book Matching

The plugin uses KOReader's partial MD5 binary hash — the same algorithm KOReader uses internally. It samples 1KB chunks at exponential positions (256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 1GB) and hashes them together. Fast, reliable, path-independent.

**For a match, the exact same file must exist in both KOReader and Jellyfin.** Same title different edition? Won't match. Downloaded via OPDS from Jellyfin? Will match perfectly.

When a book matches:
- ✅ Progress shows in Jellyfin UI
- ✅ Book marked as "In Progress" or "Finished"
- ✅ Last played date updates

When it doesn't match:
- ⚠️ Progress still syncs between KOReader devices
- ⚠️ Progress won't appear in Jellyfin UI

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/plugins/koreader/v1/healthcheck` | GET | Health check |
| `/plugins/koreader/v1/users/auth` | GET | Authenticate user |
| `/plugins/koreader/v1/syncs/progress/:document` | GET | Get progress |
| `/plugins/koreader/v1/syncs/progress` | PUT | Update progress |

All endpoints except `/healthcheck` require `x-auth-user` and `x-auth-key` headers.

```bash
# Get reading progress
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 5f4dcc3b5aa765d61d8327deb882cf99" \
  https://jellyfin.example.com/plugins/koreader/v1/syncs/progress/abc123def456
```

## Conflict Resolution

When the same book is read on multiple devices, the plugin keeps the furthest progress. Device A at 45% and Device B at 60%? Both sync to 60%.

## Data Storage

Progress files are stored under Jellyfin's plugin config directory:

```
<plugin-config>/KoReaderSync/<user-id>/<document-hash>.json
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

## Troubleshooting

**Connection failed**
- Verify the URL includes `/plugins/koreader/v1`
- Test: `curl https://your-server/plugins/koreader/v1/healthcheck`
- Ensure plugin is installed and Jellyfin restarted

**Authentication failed**
- Check username and password match Jellyfin exactly
- Use Jellyfin credentials, not an API key
- Check Jellyfin logs for errors

**Progress not syncing**
- Verify both devices use the same server and credentials
- Enable automatic sync in KOReader settings
- Try closing and reopening the book

**Progress not showing in Jellyfin UI**
- Use KOReader's default **Binary** matching method
- The exact same file must exist in both Jellyfin and KOReader
- Download books via OPDS plugin for guaranteed matches
- Progress still syncs between KOReader devices even without Jellyfin UI match

## Development

### Building

```bash
git clone https://github.com/jakepi84/JellyfinKoReaderSync.git
cd JellyfinKoReaderSync
dotnet restore
dotnet build --configuration Release

# DLL output:
# Jellyfin.Plugin.KoReaderSync/bin/Release/net9.0/Jellyfin.Plugin.KoReaderSync.dll
```

### Project Structure

```
JellyfinKoReaderSync/
├── Jellyfin.Plugin.KoReaderSync/
│   ├── Configuration/          # Plugin configuration
│   ├── Models/                 # Data transfer objects
│   ├── Services/               # Sync management logic
│   ├── KoReaderSyncApi.cs      # API controller
│   ├── KoReaderSyncPlugin.cs   # Plugin entry point
│   └── PluginServiceRegistrator.cs
├── manifest.json               # Plugin manifest
├── Directory.Build.props       # Version management
└── build-release.sh            # Build script
```

### Versioning

Version is managed in `Directory.Build.props`. Update the `<Version>` value, commit, and push — the GitHub Actions workflow handles building, updating `manifest.json`, and creating the release.

## Contributing

Pull requests welcome. Good areas: diagnostics/logging, large library performance, web-based config UI, audiobook progress tracking, tests.

## License

MIT — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Jellyfin](https://jellyfin.org/) — free software media system
- [KOReader](https://koreader.rocks/) — ebook reader application
- [KOReader Sync Server](https://github.com/koreader/koreader-sync-server) — reference implementation

## Support

- **Bug reports**: [GitHub Issues](https://github.com/jakepi84/JellyfinKoReaderSync/issues)
- **Releases**: [GitHub Releases](https://github.com/jakepi84/JellyfinKoReaderSync/releases)

---

**Maintained with ❤️ by AI (under human supervision). Built to keep your reading progress in sync, one chapter at a time.**