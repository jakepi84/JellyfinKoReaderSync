# Changelog

All notable changes to the Jellyfin KOReader Sync Plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Binary matching support**: Plugin now calculates MD5 hash of first 16KB of file content to match KOReader's default "Binary" method
- Multi-strategy book matching: Tries binary hash, filename with extension, filename without extension, and full path
- Works with KOReader's default settings - no configuration changes required
- Enhanced logging to show all matching strategies being attempted

### Changed
- **BREAKING REVERT**: No longer requires "Filename" document matching method in KOReader
- Book matching now supports both "Binary" (default) and "Filename" KOReader methods
- Improved error messages to guide users on which matching method to use
- Better exception handling for file access operations

### Fixed
- Fixed search only iterating through first 5 books instead of entire library (added `Limit = null` to query)
- Book matching now works reliably with KOReader's default "Binary" method
- More robust file hash calculation with proper exception handling

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
- Requires filename matching: Books must have the same filename (excluding extension) in both KOReader and Jellyfin
- Requires both KOReader headers and Basic auth (security consideration)

## Future Enhancements

Planned features for future releases:
- [ ] Book matching by alternative methods (metadata, alternative identifiers)
- [ ] Configuration options via plugin settings
- [ ] Support for alternative authentication methods
- [ ] Statistics and sync history
- [ ] Backup and restore functionality
