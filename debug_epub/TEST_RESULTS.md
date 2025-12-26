# Filename Matching Test Results - UPDATED

## Test File
- **Filename in Jellyfin**: `101 Conversation Starters for Couples - Gary Chapman.epub`
- **Filename in KOReader (via OPDS)**: `Gary Chapman - 101 Conversation Starters for Couples.epub`
- **Location**: `debug_epub/`
- **File Size**: 6,512,223 bytes

## Key Discovery: OPDS Plugin Transforms Filenames
The `jellyfin-plugin-opds` plugin renames files to **Author - Title** format when copying to KOReader devices. This is different from Jellyfin's storage format which uses **Title - Author**.

## Hash Calculations

### 1. Binary Hash (Partial MD5 - KOReader's default "Binary" method)
```
abd774f2d69d96308dcc6fe4c7f15f00
```
- Algorithm: Samples at exponential intervals (256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB)
- Status: ✓ Correctly calculated

### 2. Filename Hash - Jellyfin Format (Title - Author)
```
fd0ba83eac5750f2e1f8d15bb74a95c7
```
- String hashed: `101 Conversation Starters for Couples - Gary Chapman.epub`
- Status: Matches Jellyfin storage

### 3. Filename Hash - OPDS Format (Author - Title) ⭐
```
9a850ac020ae0bdbd2bfd73df6ac9354
```
- String hashed: `Gary Chapman - 101 Conversation Starters for Couples.epub`
- Status: ✓ **Matches what KOReader sends!**

## What KOReader Sends

When syncing with the OPDS plugin:
```
9a850ac020ae0bdbd2bfd73df6ac9354
```

**Analysis:**
- ✓ This hash matches the author-first filename format
- ✓ The plugin now correctly handles this transformation
- ✓ Books will match when using OPDS plugin to copy EPUBs to KOReader

## Plugin Matching Capability

✅ **Filename matching NOW WORKS with OPDS plugin!**
- Plugin correctly handles author-first filename format
- Automatically tries both "Title - Author" and "Author - Title" formats
- Works with the jellyfin-plugin-opds plugin that users are actually using

## How the Plugin Now Handles Filenames

The updated plugin tries these filename variations in order:
1. Binary hash (most reliable)
2. Original filename as-is
3. Filename without extension
4. Full path
5. Item metadata name
6. **Author-first format** (OPDS plugin format) ⭐ NEW
7. Filename without author
8. Normalized variations
9. Item ID variations (for other OPDS-based plugins)

## Recommendation

**The plugin now works correctly with the OPDS plugin!**
- Deploy the updated DLL
- Files copied via OPDS plugin to KOReader will match
- Progress will sync seamlessly
- No additional configuration needed

## Technical Notes

- Binary hash calculation: ✓ Uses KOReader's partial MD5 algorithm
- Filename hash calculation: ✓ Handles both title-first and author-first formats
- OPDS compatibility: ✓ Now accounts for filename transformations
- Both matching methods are properly implemented

