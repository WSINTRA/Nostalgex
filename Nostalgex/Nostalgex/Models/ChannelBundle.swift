import Foundation

// MARK: - JSON config (Codable)

struct ChannelBundleDefinition: Codable {
    let id: String
    let name: String
    let description: String?
    let channelIDs: [Int]
    let activeMonths: [Int]?  // e.g. [10, 11, 12, 1] for Oct-Jan. nil = always visible

    func toChannelBundle(enabled: Bool = true) -> ChannelBundle {
        ChannelBundle(
            id: id,
            name: name,
            description: description,
            channelIDs: channelIDs,
            activeMonths: activeMonths,
            enabled: enabled
        )
    }
}

// MARK: - Runtime model

struct ChannelBundle: Identifiable {
    let id: String
    let name: String
    let description: String?
    let channelIDs: [Int]
    let activeMonths: [Int]?
    var enabled: Bool = true

    /// Whether this bundle should be visible right now based on activeMonths
    /// September is special: only active from Sep 15+ (late September)
    var isInSeason: Bool { isInSeason(on: Date()) }

    /// Date-injectable so the seasonal gate can be tested without waiting for October.
    func isInSeason(on now: Date) -> Bool {
        guard let months = activeMonths else { return true }
        let cal = Calendar.current
        let currentMonth = cal.component(.month, from: now)
        guard months.contains(currentMonth) else { return false }
        // Late September gate: if September is in the list, only allow from the 15th onward
        if currentMonth == 9 {
            let day = cal.component(.day, from: now)
            return day >= 15
        }
        return true
    }
}
