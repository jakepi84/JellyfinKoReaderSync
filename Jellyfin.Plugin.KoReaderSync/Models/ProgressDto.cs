namespace Jellyfin.Plugin.KoReaderSync.Models;

/// <summary>
/// Represents the reading progress data synced with KOReader.
/// This matches the format expected by the KOReader Progress Sync API.
/// </summary>
public class ProgressDto
{
    /// <summary>
    /// Gets or sets the document identifier (MD5 hash of the book).
    /// KOReader uses MD5 hash of the file content or filename to identify books.
    /// </summary>
    public string Document { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the reading progress percentage (0.0 to 1.0).
    /// Example: 0.45 means 45% through the book.
    /// </summary>
    public double Percentage { get; set; }

    /// <summary>
    /// Gets or sets the reading progress position string.
    /// This is a KOReader-specific position string (e.g., "/body/DocFragment[20]/body/p[22]/img.0").
    /// </summary>
    public string Progress { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the device name that last synced this progress.
    /// Example: "PocketBook", "Kindle", "Kobo", etc.
    /// </summary>
    public string Device { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the unique device identifier.
    /// Each KOReader device has a unique UUID.
    /// </summary>
    public string? DeviceId { get; set; }

    /// <summary>
    /// Gets or sets the timestamp when this progress was last updated (Unix timestamp).
    /// </summary>
    public long Timestamp { get; set; }
}
