# Changelog

All notable changes to the Jellyfin KOReader Sync Plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **BREAKING**: Refactored book identification to use filename-based matching
- Users must now set "Document matching method" to "Filename" in KOReader Progress Sync settings
- Book matching now uses MD5 hash of filename (without extension) instead of file content hash
- Updated documentation to require filename matching configuration

### Removed
- Removed ISBN-based matching references from documentation
- Removed file content hash calculation method

### Fixed
- Book matching now works reliably when KOReader is configured with filename document matching

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
