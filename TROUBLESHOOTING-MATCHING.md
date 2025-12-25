# Troubleshooting Book Matching Issues

This guide helps diagnose and resolve issues when KOReader books are not matching with Jellyfin library items.

## Understanding Book Matching

The plugin uses multiple strategies to match books between KOReader and Jellyfin:

### Binary Matching (Default - Most Reliable)
- **Method**: MD5 hash of the first 16KB of file content
- **Advantage**: Works regardless of filename or path
- **Requirement**: Files must be IDENTICAL (same edition, same format)

### Filename Matching (Alternative)
- **Method**: MD5 hash of the file path
- **Challenge**: Path on KOReader device differs from Jellyfin
- **Variations**: The plugin tries filename with/without extension, normalized text

## Common Issues and Solutions

### Issue 1: "No matching Jellyfin item found"

This means none of the matching strategies succeeded. Possible causes:

#### Cause A: Different File Versions
The EPUB in KOReader is a different edition/version than the one in Jellyfin.

**How to verify:**
```bash
# On your computer with Jellyfin file
md5sum "path/to/book.epub"

# On KOReader device (if you have SSH access)
md5sum "/mnt/onboard/path/to/book.epub"
```

**Solution:**
- Ensure both locations have the EXACT same file
- Copy the file from Jellyfin to KOReader (or vice versa)
- Re-sync after copying

#### Cause B: Metadata Differences
Even with "same" book, embedded metadata or formatting can differ.

**Examples:**
- Downloaded from different sources
- One has DRM removed, other doesn't
- Different compression levels in ZIP (EPUB is a ZIP file)

**Solution:**
- Use the EXACT same file in both locations
- Prefer files without DRM

#### Cause C: File Modified by KOReader
Some KOReader versions might modify EPUB files (rare).

**Solution:**
- Use KOReader's Binary matching method (default)
- Don't manually edit EPUB contents in KOReader

### Issue 2: Filename Matching Not Working

If you're using KOReader's "Filename" document matching method:

#### Check Device Path
KOReader uses the FULL path on device for filename matching:
- Example: `/mnt/onboard/Books/Author/Title.epub`
- Jellyfin has: `/media/books/Author/Title.epub`
- These hash differently!

**Solution:**
Switch to Binary matching method:
1. In KOReader: Menu → Tools → Progress sync
2. Find "Document matching method"
3. Select "Binary" (recommended)

### Issue 3: Special Characters in Filename

Filenames with special characters can cause issues:
- Different dash types: `-` (hyphen) vs `–` (EN DASH) vs `—` (EM DASH)
- Multiple spaces
- Unicode variations

**Plugin Enhancement (v1.1.0+):**
The plugin now normalizes text to handle these variations automatically.

**Manual Solution:**
Rename files to use simple characters:
- Use regular hyphen `-`
- Single spaces only
- ASCII characters when possible

## Diagnostic Steps

### Step 1: Enable Detailed Logging

Check Jellyfin logs (Dashboard → Logs) when KOReader syncs. Look for:

```
[INF] Searching through XXX book/audiobook items for document ID "abc123..."
[INF] Checking item 'Book Title' (Filename: book.epub): X hashes calculated: [hash1, hash2, hash3...]
```

This shows:
- Which books are being checked
- What hashes are calculated
- If a match is found

### Step 2: Verify Book is in Jellyfin

1. Go to Jellyfin → Books library
2. Search for the book title
3. Verify the file exists and is accessible
4. Check file isn't corrupted

### Step 3: Check KOReader Configuration

In KOReader:
1. Menu → Tools → Progress sync
2. Verify:
   - Server URL is correct
   - Authentication works (click "Login")
   - Document matching method is set (preferably "Binary")
   - Sync is enabled

### Step 4: Test with a Simple Book

Try syncing a book with a simple filename:
- No special characters
- Short filename
- Single word title

If this works, the issue is likely filename-related.

## Advanced Troubleshooting

### Get KOReader Document ID

In KOReader, you can find the document ID:

1. Enable debug logging in KOReader
2. Sync the book
3. Check KOReader logs for the document ID being sent

### Manual File Verification

Compare files byte-by-byte:

```bash
# Calculate MD5 of first 16KB
head -c 16384 /path/to/jellyfin/book.epub | md5sum
head -c 16384 /path/to/koreader/book.epub | md5sum

# These should match for binary matching to work
```

### Check for Hidden Characters

```bash
# Display filename with hidden characters
ls -la /path/to/file.epub | cat -A
```

## Best Practices

### Recommended Setup

1. **Use Binary Matching** (KOReader default)
   - Most reliable
   - Works across different devices
   - Filename independent

2. **Use Identical Files**
   - Copy files from one location to another
   - Don't re-download from different sources
   - Verify checksums match

3. **Simple Filenames**
   - Use ASCII characters
   - Avoid special characters
   - Keep names reasonably short

### File Management

```
Recommended:
✓ "Book Title - Author Name.epub"
✓ "BookTitle.epub"
✓ "2024-Book-Title.epub"

Avoid:
✗ "Book Title – Author Name.epub" (EN DASH)
✗ "Book  Title.epub" (multiple spaces)
✗ "Book/Title.epub" (slash in filename)
✗ Files with DRM
```

## Still Not Working?

If matching still fails after trying everything:

### Option 1: Accept Limited Functionality
- Progress still syncs between KOReader devices
- Just won't show in Jellyfin UI
- Reading progress is preserved

### Option 2: Report Issue
Open a GitHub issue with:
- Jellyfin logs showing matching attempts
- KOReader logs (if accessible)
- Book filename and title
- MD5 hash of first 16KB of both files

### Option 3: Manual Mapping (Future Feature)
A future version may support manual mapping:
- Manually specify which KOReader document matches which Jellyfin item
- Bypass automatic matching
- Configure via Jellyfin plugin settings

## Technical Details

### Hash Calculation Methods

The plugin calculates these MD5 hashes for each book:

1. **Binary**: MD5 of first 16384 bytes of file content
2. **Filename+Ext**: MD5 of "filename.epub"
3. **Filename**: MD5 of "filename" (no extension)
4. **Full Path**: MD5 of "/full/path/to/filename.epub"
5. **Item Name+Ext**: MD5 of "Item Name.epub"
6. **Item Name**: MD5 of "Item Name"
7. **Normalized variants** of above (handle special characters)

KOReader sends one document ID, and the plugin checks if it matches ANY of these hashes.

### Why Binary Matching is Best

Binary matching:
- ✓ Content-based (not path-dependent)
- ✓ Works after file renames
- ✓ Works across different folder structures
- ✓ Most reliable for identical files

Filename matching:
- ✗ Path-dependent
- ✗ Breaks if file moves
- ✗ Different paths on device vs server
- ✗ Less reliable

## Summary

**Most common solution:** Use KOReader's Binary matching method with identical EPUB files in both locations.

**If Binary matching fails:** The files are not identical - verify with MD5 checksums.

**If Filename matching fails:** Paths differ between device and server - switch to Binary method.

---

For more help, see:
- [Main README](README.md)
- [Installation Guide](INSTALL.md)
- [GitHub Issues](https://github.com/jakepi84/JellyfinKoReaderSync/issues)
