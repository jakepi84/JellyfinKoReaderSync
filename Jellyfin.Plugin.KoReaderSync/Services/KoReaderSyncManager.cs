using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
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
    /// The method matches books by calculating the MD5 hash of the first 16KB of each book file
    /// in the user's library and comparing it to the KOReader document hash.
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
                _logger.LogDebug(
                    "No matching Jellyfin item found for document {Document}. Progress will still sync between KOReader devices.",
                    progress.Document);
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
    /// Finds a book item in the user's library that matches the KOReader document hash.
    /// Searches through audiobooks and books, calculating MD5 hash of first 16KB of each file.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="documentHash">The KOReader document hash (MD5 of first 16KB).</param>
    /// <returns>The matching BaseItem, or null if no match found.</returns>
    private BaseItem? FindMatchingBookItem(Guid userId, string documentHash)
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
            Recursive = true
        };

        var items = _libraryManager.GetItemList(query);
        
        _logger.LogDebug("Searching through {Count} book/audiobook items for document hash {Hash}", 
            items.Count, documentHash);

        foreach (var item in items)
        {
            // Get the file path for the item
            var path = item.Path;
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                continue;
            }

            try
            {
                // Calculate MD5 hash of first 16KB
                var fileHash = CalculateFileHash(path);
                
                _logger.LogTrace("Item: {Name}, Path: {Path}, Hash: {Hash}", 
                    item.Name, path, fileHash);

                if (fileHash.Equals(documentHash, StringComparison.OrdinalIgnoreCase))
                {
                    return item;
                }
            }
            catch (Exception ex)
            {
                _logger.LogTrace(ex, "Error calculating hash for file: {Path}", path);
            }
        }

        return null;
    }

    /// <summary>
    /// Calculates the MD5 hash of the first 16KB of a file.
    /// This matches KOReader's default document hash calculation method.
    /// </summary>
    /// <param name="filePath">The path to the file.</param>
    /// <returns>The MD5 hash as a lowercase hexadecimal string.</returns>
    private static string CalculateFileHash(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        using var md5 = MD5.Create();
        
        // Read first 16KB (16384 bytes) of the file
        const int bufferSize = 16 * 1024;
        var buffer = new byte[bufferSize];
        var bytesRead = stream.Read(buffer, 0, bufferSize);
        
        // If file is smaller than 16KB, only hash what we read
        var hashBytes = md5.ComputeHash(buffer, 0, bytesRead);
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
        // For books/audiobooks, we estimate the position based on runtime if available
        if (item.RunTimeTicks.HasValue && item.RunTimeTicks.Value > 0)
        {
            userData.PlaybackPositionTicks = (long)(item.RunTimeTicks.Value * progress.Percentage);
        }
        
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
            "Updated Jellyfin progress for item '{ItemName}': {Percentage}% (User: {UserId})",
            item.Name,
            percentage,
            userId);
    }
}
