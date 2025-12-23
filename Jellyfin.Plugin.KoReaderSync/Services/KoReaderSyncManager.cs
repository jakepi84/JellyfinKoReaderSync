using System;
using System.IO;
using System.Text.Json;
using Jellyfin.Plugin.KoReaderSync.Models;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging;

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
    private readonly string _dataPath;

    /// <summary>
    /// Initializes a new instance of the <see cref="KoReaderSyncManager"/> class.
    /// </summary>
    /// <param name="logger">The logger.</param>
    /// <param name="userDataManager">The user data manager.</param>
    /// <param name="libraryManager">The library manager.</param>
    public KoReaderSyncManager(
        ILogger<KoReaderSyncManager> logger,
        IUserDataManager userDataManager,
        ILibraryManager libraryManager)
    {
        _logger = logger;
        _userDataManager = userDataManager;
        _libraryManager = libraryManager;

        // Store progress data in the Jellyfin data directory
        var pluginDataPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "jellyfin",
            "data",
            "koreader-sync");

        _dataPath = pluginDataPath;

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
    /// Note: This is a placeholder for future enhancement. Currently, KOReader progress is stored
    /// independently and can be synced across KOReader devices. Matching books to Jellyfin items
    /// and updating Jellyfin's native progress tracking would require additional implementation.
    /// </summary>
    /// <param name="userId">The user ID.</param>
    /// <param name="progress">The progress data from KOReader.</param>
    private void TryUpdateJellyfinProgress(Guid userId, ProgressDto progress)
    {
        // TODO: Implement book matching and Jellyfin progress update
        // This would require:
        // 1. Matching KOReader document hash to Jellyfin book items (by ISBN, file hash, etc.)
        // 2. Getting the User object from userId
        // 3. Updating the UserItemData with progress information
        // 4. Saving the updated data
        
        _logger.LogDebug(
            "Jellyfin native progress update not yet implemented for document {Document}",
            progress.Document);
    }
}
