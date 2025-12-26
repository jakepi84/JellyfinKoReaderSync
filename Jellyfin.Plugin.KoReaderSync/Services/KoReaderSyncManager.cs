using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Jellyfin.Data.Enums;
using Jellyfin.Plugin.KoReaderSync.Models;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;
using MediaBrowser.Model.Entities;

namespace Jellyfin.Plugin.KoReaderSync.Services;

/// <summary>
/// Manages KOReader sync operations, including storing and retrieving reading progress.
/// Progress data is stored in the Jellyfin data directory under plugin-specific folders.
/// </summary>
public class KoReaderSyncManager : IKoReaderSyncManager
{
    /// <summary>
    /// Synthetic duration for books without RunTimeTicks (1 hour in ticks).
    /// Using TimeSpan.FromHours(1).Ticks provides a clear, maintainable constant.
    /// This provides fine-grained progress tracking for books.
    /// </summary>
    private static readonly long SyntheticBookDurationTicks = TimeSpan.FromHours(1).Ticks;

    /// <summary>
    /// Common device paths where OPDS-downloaded files might be saved on e-reader devices.
    /// Used for generating filename hash variations.
    /// </summary>
    private static readonly string[] CommonDevicePaths = { "/mnt/onboard/", "/mnt/us/documents/", "/storage/emulated/0/" };

    private readonly ILogger<KoReaderSyncManager> _logger;
    private readonly IUserDataManager _userDataManager;
    private readonly ILibraryManager _libraryManager;
    private readonly IUserManager _userManager;
    private readonly string _dataPath;
    private readonly IApplicationPaths _applicationPaths;

    /// <summary>
    /// Initializes a new instance of the <see cref="KoReaderSyncManager"/> class.
    /// </summary>
    /// <param name="logger">The logger.</param>
    /// <param name="userDataManager">The user data manager.</param>
    /// <param name="libraryManager">The library manager.</param>
    /// <param name="applicationPaths">The Jellyfin application paths provider.</param>
    /// <param name="userManager">The user manager.</param>
    public KoReaderSyncManager(
        ILogger<KoReaderSyncManager> logger,
        IUserDataManager userDataManager,
        ILibraryManager libraryManager,
        IApplicationPaths applicationPaths,
        IUserManager userManager)
    {
        _logger = logger;
        _userDataManager = userDataManager;
        _libraryManager = libraryManager;
        _applicationPaths = applicationPaths;
        _userManager = userManager;

        // Store progress data under Jellyfin's plugin configurations path (writable across OSes)
        _dataPath = Path.Combine(_applicationPaths.PluginConfigurationsPath, "KoReaderSync");

        // Ensure the data directory exists
        if (!Directory.Exists(_dataPath))
        {
            Directory.CreateDirectory(_dataPath);
            _logger.LogInformation("Created KOReader sync data directory at {Path}", _dataPath);
        }
    }

    /// <inheritdoc />
    public ProgressDto? GetProgress(Guid userId, string document)
    {
        _logger.LogDebug("Getting progress for user {UserId}, document {Document}", userId, document);

        var filePath = GetProgressFilePath(userId, document);
        if (!File.Exists(filePath))
        {
            _logger.LogDebug("No progress file found at {Path}", filePath);
            return null;
        }

        try
        {
            var json = File.ReadAllText(filePath);
            var progress = JsonSerializer.Deserialize<ProgressDto>(json);
            _logger.LogDebug("Retrieved progress: {Percentage}% for document {Document}", progress?.Percentage * 100, document);
            return progress;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reading progress file at {Path}", filePath);
            return null;
        }
    }

    /// <inheritdoc />
    public UpdateProgressResponseDto UpdateProgress(Guid userId, ProgressDto progress)
    {
        _logger.LogDebug(
            "Updating progress for user {UserId}, document {Document}: {Percentage}%",
            userId,
            progress.Document,
            progress.Percentage * 100);

        var currentTimestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        
        // Check if there's existing progress
        var existingProgress = GetProgress(userId, progress.Document);
        
        // Conflict resolution: keep the furthest progress
        if (existingProgress != null)
        {
            _logger.LogDebug(
                "Found existing progress: {ExistingPercentage}% vs new: {NewPercentage}%",
                existingProgress.Percentage * 100,
                progress.Percentage * 100);

            // If existing progress is further than new progress, keep existing
            if (existingProgress.Percentage > progress.Percentage)
            {
                _logger.LogInformation(
                    "Keeping existing progress ({Existing}%) as it's further than new progress ({New}%)",
                    existingProgress.Percentage * 100,
                    progress.Percentage * 100);
                
                // Return the existing progress with updated timestamp
                return new UpdateProgressResponseDto
                {
                    Document = progress.Document,
                    Timestamp = existingProgress.Timestamp
                };
            }
        }

        // Update timestamp to current server time
        progress.Timestamp = currentTimestamp;

        // Save the progress data
        var filePath = GetProgressFilePath(userId, progress.Document);
        try
        {
            var json = JsonSerializer.Serialize(progress, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(filePath, json);
            _logger.LogInformation(
                "Saved progress for user {UserId}, document {Document}: {Percentage}%",
                userId,
                progress.Document,
                progress.Percentage * 100);

            // Try to update Jellyfin's native progress tracking if we can match the book
            TryUpdateJellyfinProgress(userId, progress);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving progress file at {Path}", filePath);
            throw;
        }

        return new UpdateProgressResponseDto
        {
            Document = progress.Document,
            Timestamp = currentTimestamp
        };
    }

    /// <summary>
    /// Gets the file path for storing progress data for a specific user and document.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="document">The document identifier.</param>
    /// <returns>The full file path.</returns>
    private string GetProgressFilePath(Guid userId, string document)
    {
        // Create user-specific directory
        var userPath = Path.Combine(_dataPath, userId.ToString("N"));
        if (!Directory.Exists(userPath))
        {
            Directory.CreateDirectory(userPath);
        }

        // Use document hash as filename with .json extension
        return Path.Combine(userPath, $"{document}.json");
    }

    /// <summary>
    /// Attempts to update Jellyfin's native progress tracking by matching the KOReader document
    /// to a Jellyfin book item. This allows progress to be visible in the Jellyfin UI.
    /// 
    /// The method matches books by comparing the MD5 hash of the filename (without extension)
    /// to the KOReader document identifier. This requires users to configure KOReader to use
    /// "Filename" as the document matching method in Progress Sync settings.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="progress">The progress data from KOReader.</param>
    private void TryUpdateJellyfinProgress(Guid userId, ProgressDto progress)
    {
        try
        {
            _logger.LogDebug(
                "Attempting to match KOReader document {Document} to Jellyfin library item",
                progress.Document);

            // Find the matching book in the user's library
            var matchingItem = FindMatchingBookItem(userId, progress.Document);
            
            if (matchingItem == null)
            {
                _logger.LogWarning(
                    "No matching Jellyfin item found for document \"{Document}\". " +
                    "DIAGNOSTIC: Document hash was: {DocumentHash}. " +
                    "This usually means the EPUB file in KOReader is a different version than in Jellyfin. " +
                    "Verify both locations have the EXACT same file (same edition, same source). " +
                    "Progress will still sync between KOReader devices. " +
                    "The plugin supports both KOReader matching methods: 'Binary' (default, MD5 of first 16KB) and 'Filename' (MD5 of path). " +
                    "For best results, use KOReader's default 'Binary' method.",
                    progress.Document, progress.Document);
                return;
            }

            _logger.LogInformation(
                "Matched document {Document} to Jellyfin item: {ItemName} (ID: {ItemId})",
                progress.Document,
                matchingItem.Name,
                matchingItem.Id);

            // Update the user's progress in Jellyfin
            UpdateJellyfinUserData(userId, matchingItem, progress);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating Jellyfin progress for document {Document}", progress.Document);
        }
    }

    /// <summary>
    /// Finds a book item in the user's library that matches the KOReader document identifier.
    /// Matches by comparing the MD5 hash of the filename (without path or extension) to the
    /// document identifier sent by KOReader when using "Filename" document matching method.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="documentId">The KOReader document identifier (MD5 hash of filename).</param>
    /// <returns>The matching BaseItem, or null if no match found.</returns>
    private BaseItem? FindMatchingBookItem(Guid userId, string documentId)
    {
        var user = _userManager.GetUserById(userId);
        if (user == null)
        {
            _logger.LogWarning("User {UserId} not found", userId);
            return null;
        }

        // Query for all audiobooks and books in the user's library
        var query = new InternalItemsQuery(user)
        {
            IncludeItemTypes = new[] { BaseItemKind.AudioBook, BaseItemKind.Book },
            Recursive = true,
            Limit = null // Remove default limit to retrieve all items
        };

        var items = _libraryManager.GetItemList(query);
        
        _logger.LogInformation(
            "Searching through {Count} book/audiobook items for document ID \"{DocumentId}\". " +
            "Trying multiple matching strategies including direct item ID match, binary hash (MD5 of first 16KB), " +
            "filename variations, item names, and normalized text variations.",
            items.Count, documentId);

        // First, try direct item ID match (for OPDS-downloaded books)
        // OPDS may save books with filenames based on item IDs, and KOReader may use those IDs directly
        if (TryParseItemId(documentId, out var parsedItemId))
        {
            var directMatch = items.FirstOrDefault(item => item.Id == parsedItemId);
            if (directMatch != null)
            {
                _logger.LogInformation(
                    "✓ MATCHED! Document {DocumentId} directly to item '{Name}' (ID: {ItemId}) using direct item ID match",
                    documentId, directMatch.Name, directMatch.Id);
                return directMatch;
            }
        }

        var checkedCount = 0;
        foreach (var item in items)
        {
            // Get the file path for the item
            var path = item.Path;
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                _logger.LogTrace("Skipping item {Name}: no valid file path", item.Name);
                continue;
            }

            try
            {
                // Calculate possible MD5 hashes for this file
                // KOReader's "Filename" method uses the full path on device, but we don't know that path
                // So we try multiple matching strategies: binary hash, filename variations, item name, item ID
                var possibleHashes = CalculatePossibleFilenameHashes(path, item.Name, item.Id);
                
                checkedCount++;
                // Log first 5 items at INFO level to help troubleshooting
                if (checkedCount <= 5)
                {
                    // Build hash details string showing all hashes for first few items for detailed diagnostics
                    var hashSummary = possibleHashes.Count > 0 ? 
                        $"{possibleHashes.Count} hashes calculated: [{string.Join(", ", possibleHashes)}]" :
                        "No hashes calculated";
                    
                    _logger.LogInformation("Checking item '{Name}' (Filename: {Filename}): {HashSummary}",
                        item.Name, 
                        Path.GetFileName(path),
                        hashSummary);
                    
                    // If this is one of the first 5 items, also log the binary hash specifically for debugging
                    if (possibleHashes.Count > 0)
                    {
                        _logger.LogDebug("Binary hash (first 16KB) for '{Name}': {BinaryHash}", item.Name, possibleHashes[0]);
                    }
                }
                else
                {
                    _logger.LogDebug("Checking item '{Name}': {Count} hashes calculated", item.Name, possibleHashes.Count);
                }

                // Check if any of the possible hashes match the document ID
                for (int i = 0; i < possibleHashes.Count; i++)
                {
                    if (possibleHashes[i].Equals(documentId, StringComparison.OrdinalIgnoreCase))
                    {
                        var matchDescription = i == 0 ? "Binary (first 16KB MD5)" : 
                                              i < 5 ? $"Strategy #{i + 1}" :
                                              $"Normalized variation #{i + 1 - 4}";
                        _logger.LogInformation("✓ MATCHED! Document {DocumentId} to item '{Name}' using {MatchType}", 
                            documentId, item.Name, matchDescription);
                        return item;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogTrace(ex, "Error calculating filename hash for file: {Path}", path);
            }
        }

        return null;
    }

    /// <summary>
    /// Calculates multiple possible MD5 hashes for a file to match against KOReader's document ID.
    /// KOReader supports two document matching methods:
    /// 1. "Binary" method (default): Partial MD5 sampling file at exponential intervals - most reliable
    /// 2. "Filename" method: MD5 of just the filename (basename) - easier to implement, less reliable
    /// 
    /// We try multiple strategies:
    /// - Binary: Partial MD5 hash (samples at 256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 1GB)
    /// - Filename: MD5 of just the filename with extension (matches KOReader's "Filename" method)
    /// - Filename without extension: MD5 of filename without extension
    /// - Full path: MD5 of complete file path (KOReader may use this on some systems)
    /// - Item name (title from metadata): in case KOReader uses metadata
    /// - Author-first format: For OPDS plugin files (renames "Title - Author" to "Author - Title")
    /// - Item ID variations: for OPDS-downloaded files that may use item IDs in filenames
    /// - Normalized variations: handling spaces, hyphens, unicode characters, etc.
    /// - Additional fallback hashes: for filename variations that KOReader might create
    /// 
    /// Note: The jellyfin-plugin-opds plugin transforms filenames to "Author - Title" format,
    /// which may differ from how files are named in Jellyfin. This method handles both formats.
    /// </summary>
    /// <param name="filePath">The full path to the file in Jellyfin.</param>
    /// <param name="itemName">The item name from Jellyfin metadata (optional).</param>
    /// <param name="itemId">The Jellyfin item ID (optional).</param>
    /// <returns>A list of possible MD5 hashes, ordered by likelihood (Binary first, then Filename, etc).</returns>
    private static List<string> CalculatePossibleFilenameHashes(string filePath, string? itemName = null, Guid? itemId = null)
    {
        var hashes = new List<string>();
        
        // 1. Binary method: MD5 of first 16KB (KOReader's default)
        // This is the most reliable method as it doesn't depend on filename or path
        try
        {
            var binaryHash = CalculateBinaryHash(filePath);
            if (!string.IsNullOrEmpty(binaryHash))
            {
                hashes.Add(binaryHash);
            }
        }
        catch (IOException)
        {
            // File I/O error (file locked, deleted, etc.) - skip binary hash
            // Don't add to hash list to avoid false matches
        }
        catch (UnauthorizedAccessException)
        {
            // Permission denied - skip binary hash
            // Don't add to hash list to avoid false matches
        }
        
        // 2. Full filename with extension
        var filenameWithExt = Path.GetFileName(filePath);
        if (!string.IsNullOrEmpty(filenameWithExt))
        {
            hashes.Add(CalculateHash(filenameWithExt));
            
            // Also try normalized version (handle different space/hyphen characters)
            var normalized = NormalizeForMatching(filenameWithExt);
            if (normalized != filenameWithExt)
            {
                hashes.Add(CalculateHash(normalized));
            }
        }
        
        // 3. Filename without extension
        var filenameWithoutExt = Path.GetFileNameWithoutExtension(filePath);
        if (!string.IsNullOrEmpty(filenameWithoutExt) && filenameWithoutExt != filenameWithExt)
        {
            hashes.Add(CalculateHash(filenameWithoutExt));
            
            // Also try normalized version
            var normalized = NormalizeForMatching(filenameWithoutExt);
            if (normalized != filenameWithoutExt)
            {
                hashes.Add(CalculateHash(normalized));
            }
        }
        
        // 4. Full path
        if (!string.IsNullOrEmpty(filePath))
        {
            hashes.Add(CalculateHash(filePath));
        }
        
        // 5. Item name (from metadata) - KOReader might use the book title from metadata
        if (!string.IsNullOrEmpty(itemName))
        {
            // Try with .epub extension added
            hashes.Add(CalculateHash(itemName + ".epub"));
            // Try without extension
            hashes.Add(CalculateHash(itemName));
            
            // Try normalized versions
            var normalized = NormalizeForMatching(itemName);
            if (normalized != itemName)
            {
                hashes.Add(CalculateHash(normalized + ".epub"));
                hashes.Add(CalculateHash(normalized));
            }
            
            // Try without author information (just title)
            // For books like "101 Conversation Starters for Couples - Gary Chapman"
            if (itemName.Contains(" - "))
            {
                var parts = itemName.Split(" - ");
                var titleOnly = parts[0].Trim();
                hashes.Add(CalculateHash(titleOnly + ".epub"));
                hashes.Add(CalculateHash(titleOnly));
                
                // Try with author-first format (common with OPDS plugins)
                // "Title - Author" becomes "Author - Title"
                if (parts.Length >= 2)
                {
                    var authorFirst = parts[1].Trim() + " - " + titleOnly;
                    hashes.Add(CalculateHash(authorFirst + ".epub"));
                    hashes.Add(CalculateHash(authorFirst));
                }
            }
        }
        
        // 6. Filename variations (without author, case variations, etc)
        // KOReader might normalize or store filenames differently
        // Also handle OPDS plugin filename transformations (author - title format)
        var baseFilenameWithExt = Path.GetFileName(filePath);
        var baseFilenameNoExt = Path.GetFileNameWithoutExtension(filePath);
        
        if (!string.IsNullOrEmpty(baseFilenameWithExt))
        {
            // Try just the title part of filename (before hyphen)
            if (baseFilenameWithExt.Contains(" - "))
            {
                var parts = baseFilenameWithExt.Split(" - ");
                var titlePart = parts[0].Trim();
                hashes.Add(CalculateHash(titlePart + ".epub"));
                hashes.Add(CalculateHash(titlePart));
                
                // Try author-first format (OPDS plugin renames files this way)
                // If current filename is "Title - Author.epub", also try "Author - Title.epub"
                if (parts.Length >= 2)
                {
                    var authorFirst = parts[1].Trim() + " - " + titlePart;
                    hashes.Add(CalculateHash(authorFirst + ".epub"));
                    hashes.Add(CalculateHash(authorFirst));
                }
            }
            
            // Try with different extension casings
            hashes.Add(CalculateHash(baseFilenameNoExt + ".EPUB"));
            hashes.Add(CalculateHash(baseFilenameNoExt + ".Epub"));
        }
        
        // 7. Item ID variations (for OPDS-downloaded books)
        // OPDS may download files with item ID-based filenames
        if (itemId.HasValue && itemId.Value != Guid.Empty)
        {
            var itemIdHex = itemId.Value.ToString("N"); // 32-char hex format without hyphens
            var itemIdFormatted = itemId.Value.ToString("D"); // Standard GUID format with hyphens
            
            // Try item ID as filename (with and without extension)
            hashes.Add(CalculateHash(itemIdHex + ".epub"));
            hashes.Add(CalculateHash(itemIdHex));
            hashes.Add(CalculateHash(itemIdFormatted + ".epub"));
            hashes.Add(CalculateHash(itemIdFormatted));
            
            // Try with common device paths
            foreach (var basePath in CommonDevicePaths)
            {
                hashes.Add(CalculateHash(basePath + itemIdHex + ".epub"));
                hashes.Add(CalculateHash(basePath + itemIdFormatted + ".epub"));
            }
        }
        
        return hashes;
    }
    
    /// <summary>
    /// Normalizes a string for matching by:
    /// - Trimming whitespace
    /// - Replacing multiple spaces with single space
    /// - Replacing various dash/hyphen characters with standard hyphen
    /// - Removing zero-width characters
    /// This helps match files that have slight formatting differences.
    /// </summary>
    /// <param name="input">The string to normalize.</param>
    /// <returns>The normalized string.</returns>
    private static string NormalizeForMatching(string input)
    {
        if (string.IsNullOrEmpty(input))
        {
            return input;
        }
        
        var result = input.Trim();
        
        // Replace various dash characters with standard hyphen
        // U+2013 EN DASH, U+2014 EM DASH, U+2212 MINUS SIGN, U+FF0D FULLWIDTH HYPHEN-MINUS
        result = result.Replace('\u2013', '-')  // EN DASH
                      .Replace('\u2014', '-')   // EM DASH
                      .Replace('\u2212', '-')   // MINUS SIGN
                      .Replace('\uFF0D', '-');  // FULLWIDTH HYPHEN-MINUS
        
        // Replace multiple consecutive spaces with single space (using regex for efficiency)
        result = Regex.Replace(result, @"\s+", " ", RegexOptions.None, TimeSpan.FromMilliseconds(100));
        
        // Remove common zero-width characters
        result = result.Replace("\u200B", "", StringComparison.Ordinal)  // ZERO WIDTH SPACE
                      .Replace("\uFEFF", "", StringComparison.Ordinal);  // ZERO WIDTH NO-BREAK SPACE
        
        return result;
    }
    
    /// <summary>
    /// Tries to parse a document ID as a Jellyfin item ID.
    /// OPDS-downloaded books may use the Jellyfin item ID as the document identifier.
    /// Handles both hyphenated GUID format and 32-character hex format (without hyphens).
    /// </summary>
    /// <param name="documentId">The document ID to parse.</param>
    /// <param name="itemId">The parsed item ID if successful.</param>
    /// <returns>True if the document ID could be parsed as a valid item ID; otherwise, false.</returns>
    private static bool TryParseItemId(string documentId, out Guid itemId)
    {
        itemId = Guid.Empty;
        
        if (string.IsNullOrEmpty(documentId))
        {
            return false;
        }
        
        // Try parsing as-is (might have hyphens)
        if (Guid.TryParse(documentId, out itemId))
        {
            return true;
        }
        
        // Try parsing as 32-character hex string (GUID without hyphens)
        // Format: 8-4-4-4-12 characters with hyphens inserted
        if (documentId.Length == 32 && IsHexString(documentId))
        {
            var formattedGuid = $"{documentId.Substring(0, 8)}-{documentId.Substring(8, 4)}-{documentId.Substring(12, 4)}-{documentId.Substring(16, 4)}-{documentId.Substring(20, 12)}";
            if (Guid.TryParse(formattedGuid, out itemId))
            {
                return true;
            }
        }
        
        return false;
    }
    
    /// <summary>
    /// Checks if a string contains only hexadecimal characters (0-9, a-f, A-F).
    /// </summary>
    /// <param name="value">The string to check.</param>
    /// <returns>True if the string contains only hex characters; otherwise, false.</returns>
    private static bool IsHexString(string value)
    {
        foreach (var c in value)
        {
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            {
                return false;
            }
        }
        return true;
    }
    
    /// <summary>
    /// Calculates the partial MD5 hash of a file using KOReader's algorithm.
    /// This matches KOReader's "Binary" document matching method (the default).
    /// 
    /// KOReader uses a sophisticated partial MD5 algorithm that samples the file at exponential intervals:
    /// - Samples at positions: 256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 1GB
    /// - Each sample is 1KB (1024 bytes)
    /// - Uses exponential spacing (step << (2*i)) to cover the entire file with heavier weight at start
    /// - This approach is robust against file modifications while being fast to compute
    /// 
    /// Reference: https://github.com/koreader/koreader/blob/main/frontend/util.lua#L1104-L1128
    /// </summary>
    /// <param name="filePath">The full path to the file.</param>
    /// <returns>The partial MD5 hash as a lowercase hexadecimal string, or empty string on error.</returns>
    /// <exception cref="IOException">Thrown when file cannot be read due to I/O error.</exception>
    /// <exception cref="UnauthorizedAccessException">Thrown when access to file is denied.</exception>
    private static string CalculateBinaryHash(string filePath)
    {
        if (!File.Exists(filePath))
        {
            return string.Empty;
        }
        
        const int step = 1024; // 1KB step size
        const int chunkSize = 1024; // Read 1KB chunks
        
        try
        {
            using var fileStream = File.OpenRead(filePath);
            
            // Use incremental MD5 calculation for the partial hash algorithm
            using var md5 = MD5.Create();
            var buffer = new byte[chunkSize];
            
            // Sample file at exponential intervals: 256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB, 4MB, 16MB, 64MB, 1GB
            // Loop: for i = -1 to 10
            // Position: step << (2*i) = 1024 * 4^i
            for (int i = -1; i <= 10; i++)
            {
                // Calculate position: 1024 * 4^i
                long position = (long)step * (long)Math.Pow(4, i);
                
                // Seek to position (will not go beyond file size)
                if (position >= fileStream.Length)
                {
                    break;
                }
                
                fileStream.Seek(position, SeekOrigin.Begin);
                
                // Read 1KB from this position
                int bytesRead = fileStream.Read(buffer, 0, chunkSize);
                if (bytesRead > 0)
                {
                    md5.TransformBlock(buffer, 0, bytesRead, null, 0);
                }
                else
                {
                    break;
                }
            }
            
            // Finalize the MD5 hash
            md5.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            var hashBytes = md5.Hash;
            return Convert.ToHexString(hashBytes).ToLowerInvariant();
        }
        catch
        {
            // File operations can fail - return empty string
            return string.Empty;
        }
    }
    
    /// <summary>
    /// Calculates the MD5 hash of a string.
    /// </summary>
    /// <param name="input">The string to hash.</param>
    /// <returns>The MD5 hash as a lowercase hexadecimal string.</returns>
    private static string CalculateHash(string input)
    {
        var inputBytes = Encoding.UTF8.GetBytes(input);
        var hashBytes = MD5.HashData(inputBytes);
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }

    /// <summary>
    /// Updates Jellyfin's UserItemData with reading progress from KOReader.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="item">The book item.</param>
    /// <param name="progress">The progress data from KOReader.</param>
    private void UpdateJellyfinUserData(Guid userId, BaseItem item, ProgressDto progress)
    {
        var user = _userManager.GetUserById(userId);
        if (user == null)
        {
            _logger.LogWarning("User {UserId} not found", userId);
            return;
        }

        var userData = _userDataManager.GetUserData(user, item);
        
        // Update the percentage  
        var percentage = progress.Percentage * 100;
        
        // Calculate PlaybackPositionTicks based on percentage
        // For audiobooks with RunTimeTicks, use the actual runtime
        // For books without RunTimeTicks, use a synthetic duration
        long totalTicks;
        if (item.RunTimeTicks.HasValue && item.RunTimeTicks.Value > 0)
        {
            // Audiobooks have actual runtime - use it
            totalTicks = item.RunTimeTicks.Value;
            _logger.LogDebug("Using actual RunTimeTicks for item '{ItemName}': {Ticks}", item.Name, totalTicks);
        }
        else
        {
            // Books don't have runtime - use synthetic duration
            totalTicks = SyntheticBookDurationTicks;
            _logger.LogDebug("Using synthetic duration for book '{ItemName}': {Ticks} ticks", item.Name, totalTicks);
        }
        
        // Calculate and set the playback position
        // Use Math.Round to ensure consistent rounding behavior and avoid precision loss
        userData.PlaybackPositionTicks = (long)Math.Round(totalTicks * progress.Percentage, MidpointRounding.AwayFromZero);
        
        _logger.LogDebug(
            "Set PlaybackPositionTicks for '{ItemName}' to {Position} (of {Total} total, {Percentage}%)",
            item.Name,
            userData.PlaybackPositionTicks,
            totalTicks,
            percentage);
        
        // Set playback state based on percentage
        if (percentage >= 100)
        {
            userData.Played = true;
        }
        else if (percentage > 0)
        {
            userData.Played = false;
        }
        
        // Update last played date
        userData.LastPlayedDate = DateTime.UtcNow;
        
        // Save the updated user data
        _userDataManager.SaveUserData(user, item, userData, UserDataSaveReason.UpdateUserData, System.Threading.CancellationToken.None);
        
        _logger.LogInformation(
            "Updated Jellyfin progress for item '{ItemName}': {Percentage}% (PlaybackPositionTicks: {Position}, User: {UserId})",
            item.Name,
            percentage,
            userData.PlaybackPositionTicks,
            userId);
    }
}
