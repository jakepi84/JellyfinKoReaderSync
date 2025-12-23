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
    public string State { get; set; } = "OK";
}
