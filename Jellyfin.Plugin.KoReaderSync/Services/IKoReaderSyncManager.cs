using System;
using Jellyfin.Plugin.KoReaderSync.Models;

namespace Jellyfin.Plugin.KoReaderSync.Services;

/// <summary>
/// Interface for managing KOReader sync operations.
/// </summary>
public interface IKoReaderSyncManager
{
    /// <summary>
    /// Gets the reading progress for a specific document and user.
    /// </summary>
    /// <param name="userId">The Jellyfin user ID.</param>
    /// <param name="document">The document identifier (MD5 hash from KOReader).</param>
    /// <returns>The progress data if found, null otherwise.</returns>
    ProgressDto? GetProgress(Guid userId, string document);

    /// <summary>
    /// Updates the reading progress for a specific document and user.
    /// Implements conflict resolution: keeps the furthest progress if there's a conflict.
    /// </summary>
    /// <param name="userId">The Jellyfin user ID.</param>
    /// <param name="progress">The progress data to update.</param>
    /// <returns>The updated progress data with server timestamp.</returns>
    UpdateProgressResponseDto UpdateProgress(Guid userId, ProgressDto progress);
}
