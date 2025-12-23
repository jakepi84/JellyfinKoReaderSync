namespace Jellyfin.Plugin.KoReaderSync.Models;

/// <summary>
/// Response model for progress update requests.
/// </summary>
public class UpdateProgressResponseDto
{
    /// <summary>
    /// Gets or sets the document identifier that was updated.
    /// </summary>
    public string Document { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the timestamp when the update was processed.
    /// </summary>
    public long Timestamp { get; set; }
}
