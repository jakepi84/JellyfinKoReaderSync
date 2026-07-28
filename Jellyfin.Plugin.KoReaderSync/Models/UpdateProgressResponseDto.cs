using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.KoReaderSync.Models;

/// <summary>
/// Response model for progress update requests.
/// </summary>
public class UpdateProgressResponseDto
{
    /// <summary>
    /// Gets or sets the document identifier that was updated.
    /// </summary>
    [JsonPropertyName("document")]
    public string Document { get; set; } = string.Empty;

    /// <summary>
    /// Gets or sets the timestamp when the update was processed.
    /// </summary>
    [JsonPropertyName("timestamp")]
    public long Timestamp { get; set; }
}
