using System;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Jellyfin.Plugin.KoReaderSync.Models;
using Jellyfin.Plugin.KoReaderSync.Services;
using MediaBrowser.Controller.Authentication;
using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.KoReaderSync;

/// <summary>
/// KOReader Sync API endpoints.
/// Implements the KOReader Progress Sync API specification for syncing reading progress
/// between KOReader devices and Jellyfin.
/// </summary>
[ApiController]
[Route("plugins/koreader")]
[Produces("application/json")]
public class KoReaderSyncApi : ControllerBase
{
    private readonly ILogger<KoReaderSyncApi> _logger;
    private readonly IUserManager _userManager;
    private readonly IKoReaderSyncManager _syncManager;

    /// <summary>
    /// Initializes a new instance of the <see cref="KoReaderSyncApi"/> class.
    /// </summary>
    /// <param name="logger">The logger.</param>
    /// <param name="userManager">The user manager for authentication.</param>
    /// <param name="syncManager">The sync manager for progress operations.</param>
    public KoReaderSyncApi(
        ILogger<KoReaderSyncApi> logger,
        IUserManager userManager,
        IKoReaderSyncManager syncManager)
    {
        _logger = logger;
        _userManager = userManager;
        _syncManager = syncManager;
    }

    /// <summary>
    /// Authenticates a user using KOReader sync credentials.
    /// KOReader sends x-auth-user (username) and x-auth-key (MD5 hashed password) in headers.
    /// </summary>
    /// <returns>Authentication response indicating success or failure.</returns>
    [HttpGet("v1/users/auth")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AuthResponseDto>> AuthenticateUser()
    {
        try
        {
            _logger.LogDebug("Authentication request received");
            
            // Authenticate using custom headers
            await AuthorizeAsync().ConfigureAwait(false);
            
            _logger.LogInformation("User authenticated successfully");
            return Ok(new AuthResponseDto { Authorized = "OK" });
        }
        catch (AuthenticationException ex)
        {
            _logger.LogWarning(ex, "Authentication failed");
            return Unauthorized(new { message = "Authentication failed" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during authentication");
            return StatusCode(StatusCodes.Status500InternalServerError, new { message = "Internal server error" });
        }
    }

    /// <summary>
    /// Updates reading progress for a document.
    /// This endpoint receives progress updates from KOReader and stores them.
    /// Implements conflict resolution by keeping the furthest reading progress.
    /// </summary>
    /// <param name="progressDto">The progress data from KOReader.</param>
    /// <returns>Response with document ID and timestamp.</returns>
    [HttpPut("v1/syncs/progress")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<UpdateProgressResponseDto>> UpdateProgress([FromBody] ProgressDto progressDto)
    {
        try
        {
            _logger.LogDebug("Progress update request received for document {Document}", progressDto?.Document);

            // Validate input
            if (progressDto == null || string.IsNullOrWhiteSpace(progressDto.Document))
            {
                _logger.LogWarning("Invalid progress data: missing document field");
                return BadRequest(new { message = "Invalid progress data: document field is required" });
            }

            if (string.IsNullOrWhiteSpace(progressDto.Progress) || 
                string.IsNullOrWhiteSpace(progressDto.Device))
            {
                _logger.LogWarning("Invalid progress data: missing required fields");
                return BadRequest(new { message = "Invalid progress data: progress and device fields are required" });
            }

            // Authenticate user
            var userId = await AuthorizeAsync().ConfigureAwait(false);
            
            _logger.LogInformation(
                "Updating progress for user {UserId}, document {Document}: {Percentage}%",
                userId,
                progressDto.Document,
                progressDto.Percentage * 100);

            // Update progress using the sync manager
            var response = _syncManager.UpdateProgress(userId, progressDto);
            
            return Ok(response);
        }
        catch (AuthenticationException ex)
        {
            _logger.LogWarning(ex, "Authentication failed during progress update");
            return Unauthorized(new { message = "Authentication failed" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating progress");
            return StatusCode(StatusCodes.Status500InternalServerError, new { message = "Internal server error" });
        }
    }

    /// <summary>
    /// Gets reading progress for a specific document.
    /// Returns the stored progress data for the authenticated user and document.
    /// </summary>
    /// <param name="document">The document identifier (MD5 hash).</param>
    /// <returns>The progress data if found, empty object otherwise.</returns>
    [HttpGet("v1/syncs/progress/{document}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<ProgressDto>> GetProgress([FromRoute] string document)
    {
        try
        {
            _logger.LogDebug("Progress retrieval request for document {Document}", document);

            // Validate document parameter
            if (string.IsNullOrWhiteSpace(document))
            {
                _logger.LogWarning("Invalid document parameter");
                return BadRequest(new { message = "Document parameter is required" });
            }

            // Authenticate user
            var userId = await AuthorizeAsync().ConfigureAwait(false);
            
            _logger.LogDebug("Retrieving progress for user {UserId}, document {Document}", userId, document);

            // Get progress from sync manager
            var progress = _syncManager.GetProgress(userId, document);
            
            if (progress == null)
            {
                _logger.LogDebug("No progress found for document {Document}", document);
                // Return empty object when no progress is found (per KOReader API spec)
                return Ok(new { });
            }

            _logger.LogInformation(
                "Retrieved progress for document {Document}: {Percentage}%",
                document,
                progress.Percentage * 100);
            
            return Ok(progress);
        }
        catch (AuthenticationException ex)
        {
            _logger.LogWarning(ex, "Authentication failed during progress retrieval");
            return Unauthorized(new { message = "Authentication failed" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving progress");
            return StatusCode(StatusCodes.Status500InternalServerError, new { message = "Internal server error" });
        }
    }

    /// <summary>
    /// Health check endpoint to verify the service is running.
    /// </summary>
    /// <returns>Health status response.</returns>
    [HttpGet("v1/healthcheck")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult<HealthCheckResponseDto> HealthCheck()
    {
        _logger.LogDebug("Health check request received");
        return Ok(new HealthCheckResponseDto { State = "OK" });
    }

    /// <summary>
    /// Authenticates a user using KOReader's authentication method.
    /// KOReader sends credentials via custom headers:
    /// - x-auth-user: The username
    /// - x-auth-key: MD5 hash of the password
    /// 
    /// This method supports two authentication modes:
    /// 1. KOReader headers + Basic auth (most secure): Validates password against Jellyfin
    /// 2. KOReader headers only (fallback): Validates username exists in Jellyfin
    /// </summary>
    /// <returns>The authenticated user's ID.</returns>
    /// <exception cref="AuthenticationException">Thrown when authentication fails.</exception>
    private async Task<Guid> AuthorizeAsync()
    {
        // Get authentication headers sent by KOReader
        Request.Headers.TryGetValue("x-auth-user", out var authUser);
        Request.Headers.TryGetValue("x-auth-key", out var authKey);

        _logger.LogDebug("Auth attempt - User: {User}, Key present: {HasKey}", authUser.ToString(), !string.IsNullOrEmpty(authKey));

        if (string.IsNullOrWhiteSpace(authUser) || string.IsNullOrWhiteSpace(authKey))
        {
            _logger.LogWarning("Missing authentication headers");
            throw new AuthenticationException("Authentication headers (x-auth-user, x-auth-key) are required");
        }

        // Check if Basic auth is also provided (most secure approach)
        if (Request.Headers.TryGetValue("Authorization", out var authHeader) && 
            !string.IsNullOrEmpty(authHeader))
        {
            try
            {
                var authHeaderValue = AuthenticationHeaderValue.Parse(authHeader!);
                if (authHeaderValue.Scheme.Equals("Basic", StringComparison.OrdinalIgnoreCase) &&
                    !string.IsNullOrEmpty(authHeaderValue.Parameter))
                {
                    var credentialBytes = Convert.FromBase64String(authHeaderValue.Parameter);
                    var credentials = Encoding.UTF8.GetString(credentialBytes).Split(':', 2);
                    
                    if (credentials.Length == 2)
                    {
                        var username = credentials[0];
                        var password = credentials[1];

                        // Verify username matches
                        if (!username.Equals(authUser, StringComparison.OrdinalIgnoreCase))
                        {
                            _logger.LogWarning("Username mismatch: x-auth-user != Basic auth username");
                            throw new AuthenticationException("Username mismatch");
                        }

                        // Verify the password hash matches what KOReader sent
                        var passwordHash = ComputeMD5(password);
                        if (!passwordHash.Equals(authKey, StringComparison.OrdinalIgnoreCase))
                        {
                            _logger.LogWarning("Password hash mismatch");
                            throw new AuthenticationException("Invalid credentials");
                        }

                        // Authenticate with Jellyfin
                        var user = await _userManager.AuthenticateUser(
                                username,
                                password,
                                Request.HttpContext.Connection.RemoteIpAddress?.ToString() ?? "Unknown",
                                false)
                            .ConfigureAwait(false);

                        if (user == null)
                        {
                            _logger.LogWarning("Jellyfin authentication failed for user {User}", username);
                            throw new AuthenticationException("Invalid Jellyfin credentials");
                        }

                        _logger.LogInformation("User {User} authenticated successfully via Basic auth", username);
                        return user.Id;
                    }
                }
            }
            catch (AuthenticationException)
            {
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error parsing Basic auth header");
            }
        }

        // Fallback: Authenticate using only KOReader headers
        // SECURITY NOTE: This mode validates username existence but does NOT verify the password hash.
        // This is less secure than Basic auth mode but provides compatibility with standard KOReader
        // sync protocol. Reading progress data is considered low-sensitivity, but users should be
        // aware that anyone with network access who knows a username can access that user's sync data.
        // For enhanced security, configure KOReader to send Basic Authentication headers.
        _logger.LogDebug("Attempting authentication with KOReader headers only for user {User}", authUser);
        
        var authKeyStr = authKey.ToString();
        _logger.LogInformation("Authentication mode: KOReader headers only (password hash not validated, x-auth-key: {KeyPrefix}...)", 
            authKeyStr.Length > 8 ? authKeyStr.Substring(0, 8) : authKeyStr);
        
        var jellyfinUser = _userManager.GetUserByName(authUser!);
        if (jellyfinUser == null)
        {
            _logger.LogWarning("User {User} not found in Jellyfin", authUser);
            throw new AuthenticationException("User not found");
        }

        _logger.LogInformation("User {User} authenticated successfully via KOReader headers (security mode: username-only)", authUser);
        return jellyfinUser.Id;
    }

    /// <summary>
    /// Computes the MD5 hash of a string (used for password hashing compatibility with KOReader).
    /// </summary>
    /// <param name="input">The input string to hash.</param>
    /// <returns>The MD5 hash as a lowercase hexadecimal string.</returns>
    private static string ComputeMD5(string input)
    {
        using var md5 = MD5.Create();
        var inputBytes = Encoding.UTF8.GetBytes(input);
        var hashBytes = md5.ComputeHash(inputBytes);
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }
}
