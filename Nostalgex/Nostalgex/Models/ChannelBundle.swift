import Foundation

// MARK: - JSON config (Codable)

struct ChannelBundleDefinition: Codable {
    let id: String
    let name: String
    let description: String?
    let channelIDs: [Int]
    let activeMonths: [Int]?  // e.g. [10, 11, 12, 1] for Oct-Jan. nil = always visible
    /// Starts the season before the first of its first month. See `SeasonStart`.
    var seasonStart: SeasonStart? = nil

    func toChannelBundle(enabled: Bool = true) -> ChannelBundle {
        ChannelBundle(
            id: id,
            name: name,
            description: description,
            channelIDs: channelIDs,
            activeMonths: activeMonths,
            enabled: enabled,
            seasonStart: seasonStart
        )
    }
}

/// A season that starts on a day worked out each year, rather than on the first of a
/// month. TIS THE SEASON is `activeMonths: [12]` with
/// `seasonStart: { "relativeTo": "usThanksgiving", "days": -7 }`: in season from a week
/// before US Thanksgiving (the fourth Thursday of November) to the end of December.
///
/// The bundle is in season from local midnight on that day to the end of that day's
/// month, and then in its `activeMonths` as before, so the start has to fall in the
/// month before the first active month (SeasonalBundleTests checks the shipped config).
/// An anchor this build does not know is ignored and `activeMonths` alone decides.
/// Mirrored in scripts/nostalgex-season.js; shared vectors in scripts/season-golden.json.
struct SeasonStart: Codable, Equatable {
    /// "usThanksgiving" is the only anchor so far.
    let relativeTo: String?
    /// Days from the anchor; negative is before it. Absent means the anchor day itself.
    let days: Int?

    static let usThanksgivingAnchor = "usThanksgiving"

    /// Local midnight of the start in `year`, or nil for an unknown anchor.
    func date(inYear year: Int, calendar: Calendar) -> Date? {
        guard relativeTo == Self.usThanksgivingAnchor,
              let anchor = Self.usThanksgiving(year: year, calendar: calendar),
              let day = calendar.date(byAdding: .day, value: days ?? 0, to: anchor) else { return nil }
        return calendar.startOfDay(for: day)
    }

    /// Local midnight of US Thanksgiving, the fourth Thursday of November.
    static func usThanksgiving(year: Int, calendar: Calendar) -> Date? {
        guard let november1 = calendar.date(from: DateComponents(year: year, month: 11, day: 1)) else { return nil }
        let weekday = calendar.component(.weekday, from: november1)   // 1 Sunday ... 5 Thursday
        let firstThursday = 1 + (5 - weekday + 7) % 7
        return calendar.date(from: DateComponents(year: year, month: 11, day: firstThursday + 21))
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
    var seasonStart: SeasonStart? = nil

    /// Months and days are Gregorian, in the device's time zone, whatever calendar the
    /// device is set to: `activeMonths` and US Thanksgiving are Gregorian dates.
    static var seasonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Whether this bundle should be visible right now based on activeMonths
    /// September is special: only active from Sep 15+ (late September)
    var isInSeason: Bool { isInSeason(on: Date()) }

    /// Date-injectable so the seasonal gate can be tested without waiting for October.
    func isInSeason(on now: Date, calendar: Calendar = ChannelBundle.seasonCalendar) -> Bool {
        guard let months = activeMonths else { return true }
        let cal = calendar
        let currentMonth = cal.component(.month, from: now)
        if months.contains(currentMonth) {
            // Late September gate: if September is in the list, only allow from the 15th onward
            if currentMonth == 9 {
                let day = cal.component(.day, from: now)
                return day >= 15
            }
            return true
        }
        // A season that starts early: from `seasonStart` to the end of that month.
        guard let start = seasonStartDate(inYearOf: now, calendar: cal) else { return false }
        return now >= start && cal.component(.month, from: start) == currentMonth
    }

    /// This year's early start (`seasonStart`), or nil.
    func seasonStartDate(inYearOf now: Date, calendar: Calendar = ChannelBundle.seasonCalendar) -> Date? {
        guard activeMonths != nil, let seasonStart else { return nil }
        return seasonStart.date(inYear: calendar.component(.year, from: now), calendar: calendar)
    }

    private static let monthAbbreviations = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                                             "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// The Settings note for a seasonal bundle outside its season: "Spotlighted OCT", or
    /// "Spotlighted NOV 19 to DEC 31" for one with `seasonStart` (this year's dates, which
    /// outside the season are the next ones). Empty for a bundle that is not seasonal.
    /// Mirrors `seasonalSpotlightLabel` in scripts/nostalgex-season.js.
    func spotlightLabel(now: Date, calendar: Calendar = ChannelBundle.seasonCalendar) -> String {
        guard let months = activeMonths, !months.isEmpty else { return "" }
        let abbr: (Int) -> String? = { m in (1...12).contains(m) ? Self.monthAbbreviations[m - 1] : nil }
        if let start = seasonStartDate(inYearOf: now, calendar: calendar),
           let last = months.last, let lastName = abbr(last) {
            let startMonth = calendar.component(.month, from: start)
            let startYear = calendar.component(.year, from: start)
            let endYear = last < startMonth ? startYear + 1 : startYear
            let lastDay = calendar.date(from: DateComponents(year: endYear, month: last, day: 1))
                .flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
            let startName = abbr(startMonth) ?? ""
            return "Spotlighted \(startName) \(calendar.component(.day, from: start)) to \(lastName) \(lastDay)"
        }
        let names = months.compactMap(abbr)
        return names.isEmpty ? "" : "Spotlighted \(names.joined(separator: ", "))"
    }
}
