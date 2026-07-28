using System.Text.Json.Serialization;

namespace Jellyfin.Plugin.KoReaderSync.Models;

/// <summary>
/// Response model for healthcheck requests.
/// </summary>
public class HealthCheckResponseDto
{
    /// <summary>
    /// Gets or sets the service state.
    /// Returns "OK" when the service is healthy.
    /// </summary>
    [JsonPropertyName("state")]
    public string State { get; set; } = "OK";
}
