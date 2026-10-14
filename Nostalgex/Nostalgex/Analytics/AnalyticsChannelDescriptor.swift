import Foundation

/// Cross-user-comparable identity for a Channel that a signal is about.
///
/// Channel numbers alone can't be compared across users: bundles are opt-in and
/// dynamic collection channels are ordered per-user, so CH 74 on one Apple TV is
/// not the same lineup slot as CH 74 on another. Every signal that mentions a
/// channel therefore also carries this descriptor so the dashboard has a stable
/// grouping.
///
/// For **static** channels (defined in the app's own `channels.json`) we send:
/// - `channelType = "static"`
/// - `channelID`  = the fixed id from `channels.json` (1..414 today; runtime
///   collection and franchise channels take ids from 1,000,000 up, see
///   `ChannelIDSpace`), same on every device — this is what "which channel is
///   watched most" filters on.
/// - `channelName` = the fixed display name from the app's **bundled**
///   `channels.json` for that id (e.g. `REWATCHABLES MOVIES`, `KIDZ CARTOONS`).
///   Deliberately NOT `Channel.name` at runtime — that could be overridden by
///   a server-hosted `channels.json` (`AppState.loadChannelConfig()` tries
///   `serverURL/channels.json` before the bundle), and analytics must never
///   carry a string the user's server could have influenced.
/// - `bundle`     = the channel's `category`, which is the bundle key
///   (`nostalgex`, `kids`, `truecrime`, `high-rotation`, ...).
///
/// For **dynamic collection** channels (built from a user's own Plex/Jellyfin/Emby
/// collections, or from the franchises found in their library, at runtime by
/// `AppState.materializeDynamicChannels`) we send:
/// - `channelType = "collection"`
/// - no `channelID` (the per-install id would leak user ordering)
/// - **no `channelName`** — the runtime name is the user's own collection
///   title (or a franchise name derived from their library), which must never
///   leave the device.
/// - `bundle`     = the collection category bundle key
///   (`collections-franchises`, `collections-custom`; `collections-actors` is
///   retired but may still arrive from an older build).
///
/// A grep for `channelType`, `channelID`, `channelName`, or `bundle` outside
/// this file / the event catalog should return nothing — the descriptor is
/// the only path.
struct AnalyticsChannelDescriptor: Sendable, Equatable {
    /// Where the channel came from. Fixed vocabulary; never a Plex collection
    /// title, Jellyfin folder name, or anything else the user typed.
    enum Kind: String, Sendable {
        /// Predefined in `channels.json`, same identity across every install.
        case `static`
        /// Built at runtime from a Plex/Jellyfin/Emby collection the user
        /// chose to enable. Identity is per-install, so no id and no name.
        case collection
    }

    let kind: Kind
    /// `channels.json` id. Non-nil only for `.static`.
    let channelID: Int?
    /// Display name from the app's **bundled** `channels.json`. Non-nil only
    /// for `.static` channels whose id is present in the bundled catalog.
    /// Collection channels ALWAYS carry `nil` here.
    let channelName: String?
    /// Bundle key the channel lives in. Fixed vocabulary from `channels.json`
    /// (`nostalgex`, `kids`, `truecrime`, `essentials`, `premium`, `arthouse`,
    /// `adventureland`, `sports`, `decades`, `franchises`, `streamers`,
    /// `seasonal`, `high-rotation`, `franchise` [legacy singular]) or a
    /// `collections-*` variant for dynamic collection bundles.
    let bundle: String

    /// Wire-form parameters merged onto every signal that carries a channel.
    /// Keys mirror the `channels.json` vocabulary so the dashboard can
    /// group directly on them.
    var wireParameters: [String: String] {
        var params: [String: String] = [
            "channelType": kind.rawValue,
            "bundle": bundle,
        ]
        if let id = channelID {
            params["channelID"] = String(id)
        }
        if let name = channelName {
            params["channelName"] = name
        }
        return params
    }
}

extension AnalyticsChannelDescriptor {
    /// Build the descriptor for one Channel. Discrimination rule: a channel
    /// whose `category` parses as a `CollectionCategory` raw value AND has
    /// no static `rules` was materialised by `materializeCollectionChannels`,
    /// so its identity lives on the user's server and only the bundle is
    /// safe to send. Everything else is a static app-catalog channel.
    ///
    /// The `rules == nil` clause matters: the legacy `franchise` (singular)
    /// static category from `channels.json` does NOT parse as
    /// `CollectionCategory`, but a dynamic bundle key like `franchises`
    /// (plural) does — the two are deliberately named differently, and this
    /// helper leans on that. The extra `rules == nil` guard is belt-and-
    /// braces in case a future channels.json ever adds a static entry whose
    /// category collides with a CollectionCategory raw value.
    ///
    /// `staticNameLookup` is injectable for tests. The production lookup
    /// (`BundledChannelNames.name(forStaticChannelID:)`) reads from the app
    /// bundle only, never the server-hosted override — that guarantee is
    /// the whole reason we don't just use `channel.name` here.
    static func describe(
        _ channel: Channel,
        staticNameLookup: (Int) -> String? = BundledChannelNames.name(forStaticChannelID:)
    ) -> AnalyticsChannelDescriptor {
        if let category = channel.category,
           CollectionCategory(rawValue: category) != nil,
           channel.rules == nil {
            return AnalyticsChannelDescriptor(
                kind: .collection,
                channelID: nil,
                channelName: nil,      // never for collections
                bundle: "collections-\(category)"
            )
        }
        return AnalyticsChannelDescriptor(
            kind: .static,
            channelID: channel.id,
            channelName: staticNameLookup(channel.id),
            bundle: channel.category ?? "uncategorized"
        )
    }
}

/// One-shot cache of `id → name` from the **app-bundled** `channels.json`.
///
/// Loaded lazily on first access (main-thread cost is one JSON decode of a
/// ~100 KB file; happens once per app process) and never refreshed at runtime.
/// The whole point of caching here rather than reading `channel.name` at the
/// call site is that `channel.name` can come from a server-hosted
/// `channels.json` override (`AppState.loadChannelConfig()`), which is user-
/// controlled data — this cache is bundled-only, so analytics never carries a
/// name the user's server could have influenced.
enum BundledChannelNames {
    /// `id → name` from the bundled catalog. Empty if the bundle doesn't
    /// contain `channels.json` (only happens when the app resource wasn't
    /// packaged, e.g. during a test that runs without the app bundle — see
    /// `AnalyticsChannelDescriptor.describe(_:staticNameLookup:)`, which lets
    /// tests inject their own lookup).
    static let names: [Int: String] = {
        let config = ChannelConfigLoader.loadBundled()
        var out: [Int: String] = [:]
        out.reserveCapacity(config.channels.count)
        for channel in config.channels {
            out[channel.id] = channel.name
        }
        return out
    }()

    /// Look up a static channel's bundled name. Returns `nil` when the id
    /// isn't in the bundle (e.g. a server-hosted `channels.json` added a
    /// channel that the shipped app doesn't know about). Callers must then
    /// omit `channelName` rather than fall back to the runtime `Channel.name`.
    static func name(forStaticChannelID id: Int) -> String? {
        names[id]
    }
}
