using Jellyfin.Plugin.KoReaderSync.Services;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;

namespace Jellyfin.Plugin.KoReaderSync;

/// <summary>
/// Registers plugin services with the dependency injection container.
/// </summary>
public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    /// <inheritdoc />
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        // Register the KOReader sync manager as a singleton service
        // This ensures a single instance manages all sync operations
        serviceCollection.AddSingleton<IKoReaderSyncManager, KoReaderSyncManager>();
    }
}
