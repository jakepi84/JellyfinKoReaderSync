# Changelog

All notable changes to the Jellyfin KOReader Sync Plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-12-23

### Added
- Initial release of Jellyfin KOReader Sync Plugin
- KOReader Progress Sync API implementation with four endpoints:
  - `GET /healthcheck` - Service health check
  - `GET /users/auth` - User authentication
  - `GET /syncs/progress/:document` - Retrieve reading progress
  - `PUT /syncs/progress` - Update reading progress
- Jellyfin user authentication integration
  - Supports both KOReader custom headers (`x-auth-user`, `x-auth-key`)
  - Requires HTTP Basic Authentication for Jellyfin user validation
- File-based progress storage in Jellyfin data directory
- Automatic conflict resolution (keeps furthest reading progress)
- Multi-device sync support
- Comprehensive documentation:
  - README with installation and setup instructions
  - API documentation with examples
  - KOReader configuration guide
- Build automation:
  - GitHub Actions workflow for automated builds
  - Package script for creating distribution archives
- Plugin manifest for Jellyfin plugin catalog

### Technical Details
- Built for Jellyfin 10.10.0+
- Targets .NET 9.0
- Compatible with KOReader Progress Sync API specification
- Progress data stored as JSON files per user
- MD5 password hashing for KOReader compatibility

### Known Limitations
- Book matching between KOReader and Jellyfin (by ISBN) not yet implemented
- Progress not visible in Jellyfin UI (planned for future release)
- Requires both KOReader headers and Basic auth (security consideration)

## Future Enhancements

Planned features for future releases:
- [ ] Book matching by ISBN to sync with Jellyfin's native progress tracking
- [ ] Book matching by file hash as fallback method
- [ ] Display reading progress in Jellyfin UI
- [ ] Configuration options via plugin settings
- [ ] Support for alternative authentication methods
- [ ] Statistics and sync history
- [ ] Backup and restore functionality
