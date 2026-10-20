import Foundation

/// Library items that stay in the library but never go on a channel.
///
/// One rule: on Emby, a Dolby Vision profile 5 file. Emby 4.10.1.0 sends profile 5 to the
/// Apple TV as plain `hvc1` with no Dolby Vision signalling, and re-encodes it for a browser
/// with no tone mapping, so both draw it green and purple. Seen 2026-10-19 on a real Apple
/// TV 4K against Chad's Emby, and measured on the lab Emby; no request we tried changes what
/// Emby sends. Profile 8 files carry an HDR10 base layer and stay. Plex and Jellyfin send
/// profile 5 correctly and are not touched. An item whose profile Emby did not report is
/// kept: this never guesses.
///
/// Applied wherever a channel pool is built from the library: the stock channels
/// (`makeFilterCache` / `filterItems`), found franchises (`rebuildFoundFranchises`) and
/// server collections (`scanCollections`). The items stay in `allItems`, so library counts,
/// enrichment and the snapshot are unchanged.
///
/// Same rule as `isLeftOffChannels` in scripts/nostalgex-channel-filter.cjs (web tuner and
/// Docker). The golden cases in scripts/filter-golden.json hold both engines to it.
enum ChannelEligibility {

    static func isLeftOffChannels(_ item: PlexMediaItem, backend: MediaBackendKind) -> Bool {
        backend == .emby && item.doviProfile == 5
    }

    /// `items` without the ones left off channels, in the same order.
    static func onChannels(_ items: [PlexMediaItem], backend: MediaBackendKind) -> [PlexMediaItem] {
        guard backend == .emby else { return items }
        return items.filter { !isLeftOffChannels($0, backend: backend) }
    }

    static func leftOffCount(_ items: [PlexMediaItem], backend: MediaBackendKind) -> Int {
        guard backend == .emby else { return 0 }
        return items.reduce(0) { $0 + (isLeftOffChannels($1, backend: backend) ? 1 : 0) }
    }
}
