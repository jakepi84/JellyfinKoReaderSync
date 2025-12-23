using System;
using System.Collections.Generic;
using Jellyfin.Plugin.KoReaderSync.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.KoReaderSync;

/// <summary>
/// KOReader Sync Plugin entry point.
/// This plugin provides an API endpoint compatible with KOReader's Progress Sync functionality,
/// allowing users to sync their book reading progress between KOReader devices and Jellyfin.
/// </summary>
public class KoReaderSyncPlugin : BasePlugin<PluginConfiguration>
{
    /// <summary>
    /// The plugin's unique identifier.
    /// </summary>
    private readonly Guid _id = new("6B0B1F98-F7B5-4E8A-9E6C-4D5A3B2E1C9A");

    /// <summary>
    /// Initializes a new instance of the <see cref="KoReaderSyncPlugin"/> class.
    /// </summary>
    /// <param name="applicationPaths">Instance of the <see cref="IApplicationPaths"/> interface.</param>
    /// <param name="xmlSerializer">Instance of the <see cref="IXmlSerializer"/> interface.</param>
    public KoReaderSyncPlugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    /// <summary>
    /// Gets the current plugin instance.
    /// </summary>
    public static KoReaderSyncPlugin? Instance { get; private set; }

    /// <inheritdoc />
    public override Guid Id => _id;

    /// <inheritdoc />
    public override string Name => "KOReader Sync";

    /// <inheritdoc />
    public override string Description => "Sync book reading progress with KOReader devices";
}
