namespace Jellyfin.Plugin.KoReaderSync.Models;

/// <summary>
/// Response model for authentication requests.
/// </summary>
public class AuthResponseDto
{
    /// <summary>
    /// Gets or sets the authorization status.
    /// Returns "OK" when authentication is successful.
    /// </summary>
    public string Authorized { get; set; } = "OK";
}
