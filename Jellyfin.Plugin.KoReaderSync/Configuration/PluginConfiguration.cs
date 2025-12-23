namespace Jellyfin.Plugin.KoReaderSync.Configuration;

/// <summary>
/// Plugin configuration.
/// Currently no configuration options are needed, but this can be extended in the future
/// to add settings like:
/// - Enable/disable automatic Jellyfin progress updates
/// - Configure book matching strategies
/// - Set conflict resolution preferences
/// </summary>
public class PluginConfiguration : MediaBrowser.Model.Plugins.BasePluginConfiguration
{
    /// <summary>
    /// Initializes a new instance of the <see cref="PluginConfiguration"/> class.
    /// </summary>
    public PluginConfiguration()
    {
    }
}
