import Foundation

/// Decides the order channels appear in the guide.
///
/// Normally that is channel number. A seasonal package is the exception: saying yes to
/// SCREAM used to scatter its four channels to 19, 77, 131 and 132, so accepting an
/// invitation looked like nothing had happened. For the month it runs, a seasonal package
/// leads the guide as a block, in the order its bundle declares, above channel one.
/// Numbers are untouched — this is only what the grid shows first.
enum GuideChannelOrder {

    static func sorted(_ channels: [Channel], seasonalFirst: [Int]) -> [Channel] {
        guard !seasonalFirst.isEmpty else {
            return channels.sorted { $0.number < $1.number }
        }
        // Position within the seasonal block, so a bundle's own ordering is preserved
        // rather than falling back to channel number inside the group.
        var rank: [Int: Int] = [:]
        for (i, id) in seasonalFirst.enumerated() where rank[id] == nil { rank[id] = i }

        let leading = channels
            .filter { rank[$0.id] != nil }
            .sorted { (rank[$0.id] ?? 0) < (rank[$1.id] ?? 0) }
        let rest = channels
            .filter { rank[$0.id] == nil }
            .sorted { $0.number < $1.number }
        return leading + rest
    }

    /// Channel IDs that should lead, taken from every seasonal bundle currently enabled
    /// and in season. A bundle without `activeMonths` is not seasonal and never leads.
    static func seasonalLeadIDs(bundles: [ChannelBundle], enabledBundleIDs: Set<String>, now: Date) -> [Int] {
        bundles
            .filter { $0.activeMonths != nil && enabledBundleIDs.contains($0.id) && $0.isInSeason(on: now) }
            .flatMap(\.channelIDs)
    }
}
