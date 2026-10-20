import XCTest
@testable import Nostalgex

/// Shared golden vectors for seasonal bundles: when one is in season, the invite, the
/// guide lead, NOT THIS YEAR and DON'T ASK AGAIN, the headline and the Settings note.
///
/// `scripts/season-golden.json` is read by this test AND by the web tuner's node test
/// (`npm run test:season`, scripts/nostalgex-season-smoke.mjs). Times in it are local
/// wall-clock times; every case runs in each zone the file lists, plus this machine's,
/// over the bundles in the bundled channels.json.
final class SeasonGoldenTests: XCTestCase {

    // MARK: - The file

    private struct Golden: Decodable {
        let zones: [String]
        let thanksgiving: [Thanksgiving]
        let inSeason: [InSeason]
        let offer: [Offer]
        let lead: [Lead]
        let answers: [Answers]
        let headline: [TextCase]
        let label: [TextCase]
    }
    private struct Def: Decodable {
        let id: String?
        let name: String?
        let activeMonths: [Int]?
        let seasonStart: SeasonStart?
    }
    private struct Thanksgiving: Decodable {
        let year: Int
        let thanksgiving: String
        let tisTheSeasonStart: String
    }
    private struct InSeason: Decodable {
        let name: String
        let bundle: String?
        let def: Def?
        let at: String
        let want: Bool
    }
    private struct Offer: Decodable {
        let name: String
        let at: String
        let on: [String]?
        let want: String?
    }
    private struct Lead: Decodable {
        let name: String
        let at: String
        let on: [String]
        let want: [String]
    }
    private struct Answers: Decodable {
        let name: String
        let steps: [Step]
    }
    private struct TextCase: Decodable {
        let bundle: String?
        let def: Def?
        let at: String
        let want: String
    }
    /// One step of an answer case. `"offer": null` is a check, so presence matters.
    private struct Step: Decodable {
        enum Kind {
            case answer(String, bundle: String)
            case offer(String?)
            case silenced(String, want: Bool)
        }
        let at: String
        let kind: Kind

        private enum CodingKeys: String, CodingKey { case answer, bundle, at, offer, silenced, want }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decode(String.self, forKey: .at)
            if let answer = try c.decodeIfPresent(String.self, forKey: .answer) {
                kind = .answer(answer, bundle: try c.decode(String.self, forKey: .bundle))
            } else if c.contains(.offer) {
                kind = .offer(try c.decodeIfPresent(String.self, forKey: .offer))
            } else {
                kind = .silenced(try c.decode(String.self, forKey: .silenced), want: try c.decode(Bool.self, forKey: .want))
            }
        }
    }

    /// Repo root, found from this source file: NostalgexTests -> Nostalgex -> root.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func golden() throws -> Golden {
        try JSONDecoder().decode(
            Golden.self,
            from: Data(contentsOf: Self.repoRoot.appendingPathComponent("scripts/season-golden.json")))
    }

    /// The bundles as the app loads them from the bundled channels.json, all off.
    private func shippedBundles() throws -> [ChannelBundle] {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "channels", withExtension: "json"))
        let config = try XCTUnwrap(ChannelConfigLoader.loadConfig(from: Data(contentsOf: url)))
        return config.bundles.map { $0.toChannelBundle(enabled: false) }
    }

    private func zones(_ g: Golden) -> [String] {
        g.zones + [TimeZone.current.identifier]
    }

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone), zone)
        return calendar
    }

    /// "2026-11-19T00:00" as local wall-clock time in `calendar`'s zone.
    private func local(_ at: String, _ calendar: Calendar) throws -> Date {
        let parts = at.split(separator: "T")
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = (parts.count > 1 ? parts[1] : "00:00").split(separator: ":").compactMap { Int($0) }
        return try XCTUnwrap(calendar.date(from: DateComponents(year: d[0], month: d[1], day: d[2],
                                                                hour: t[0], minute: t[1])), at)
    }

    private func ymd(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func bundle(_ id: String?, _ def: Def?, in bundles: [ChannelBundle]) throws -> ChannelBundle {
        if let def {
            return ChannelBundle(id: def.id ?? "def", name: def.name ?? "DEF", description: nil, channelIDs: [1],
                                 activeMonths: def.activeMonths, seasonStart: def.seasonStart)
        }
        return try XCTUnwrap(bundles.first { $0.id == id }, "no bundle \(id ?? "nil") in channels.json")
    }

    private func channelIDs(of ids: [String], in bundles: [ChannelBundle]) -> [Int] {
        ids.flatMap { id in bundles.first { $0.id == id }?.channelIDs ?? [] }
    }

    /// The names of the in-season, offer and lead vectors that fail for these bundles.
    private func windowFailures(_ g: Golden, bundles: [ChannelBundle], calendar: Calendar) throws -> [String] {
        var failed: [String] = []
        for c in g.inSeason {
            let b = try bundle(c.bundle, c.def, in: bundles)
            if b.isInSeason(on: try local(c.at, calendar), calendar: calendar) != c.want { failed.append(c.name) }
        }
        for c in g.offer {
            let offer = SeasonalPrompt.bundleToOffer(
                bundles: bundles, enabledBundleIDs: Set(c.on ?? []), now: try local(c.at, calendar),
                calendar: calendar) { _ in false }
            if offer?.id != c.want { failed.append("offer: \(c.name)") }
        }
        for c in g.lead {
            let lead = GuideChannelOrder.seasonalLeadIDs(
                bundles: bundles, enabledBundleIDs: Set(c.on), now: try local(c.at, calendar), calendar: calendar)
            if lead != channelIDs(of: c.want, in: bundles) { failed.append("lead: \(c.name)") }
        }
        return failed
    }

    // MARK: - Tests

    func testUSThanksgivingAndTheHolidayStart() throws {
        let g = try golden()
        let holiday = try XCTUnwrap(try shippedBundles().first { $0.id == "tis-the-season" })
        for zone in zones(g) {
            let cal = try calendar(zone)
            for t in g.thanksgiving {
                let thanksgiving = try XCTUnwrap(SeasonStart.usThanksgiving(year: t.year, calendar: cal))
                XCTAssertEqual(ymd(thanksgiving, cal), t.thanksgiving, "\(zone) \(t.year)")
                XCTAssertEqual(cal.component(.weekday, from: thanksgiving), 5, "\(zone) \(t.year): a Thursday")
                let start = try XCTUnwrap(holiday.seasonStartDate(inYearOf: try local("\(t.year)-06-01T12:00", cal),
                                                                  calendar: cal))
                XCTAssertEqual(ymd(start, cal), t.tisTheSeasonStart, "\(zone) \(t.year)")
                XCTAssertEqual(start, cal.startOfDay(for: start), "\(zone) \(t.year): local midnight")
            }
        }
    }

    func testInSeasonOfferAndLeadInEveryZone() throws {
        let g = try golden()
        let bundles = try shippedBundles()
        for zone in zones(g) {
            XCTAssertEqual(try windowFailures(g, bundles: bundles, calendar: try calendar(zone)), [], zone)
        }
    }

    /// The app calls these without a calendar; the default is the device's zone.
    func testTheDefaultCalendarIsLocalAndGregorian() throws {
        let g = try golden()
        let bundles = try shippedBundles()
        let here = try calendar(TimeZone.current.identifier)
        XCTAssertEqual(ChannelBundle.seasonCalendar.identifier, .gregorian)
        XCTAssertEqual(ChannelBundle.seasonCalendar.timeZone, TimeZone.current)
        for c in g.inSeason {
            let b = try bundle(c.bundle, c.def, in: bundles)
            XCTAssertEqual(b.isInSeason(on: try local(c.at, here)), c.want, c.name)
        }
    }

    func testNotThisYearAndDontAskAgainInEveryZone() throws {
        let g = try golden()
        let bundles = try shippedBundles()
        for zone in zones(g) {
            let cal = try calendar(zone)
            for a in g.answers {
                let suite = "SeasonGoldenTests.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { UserDefaults().removePersistentDomain(forName: suite) }
                var enabled: Set<String> = []
                for step in a.steps {
                    let now = try local(step.at, cal)
                    switch step.kind {
                    case let .answer(answer, bundleID):
                        let choice: SeasonalPrompt.Answer = answer == "yes" ? .yes : answer == "never" ? .never : .notNow
                        if SeasonalPrompt.record(choice, bundleID: bundleID, now: now, defaults: defaults, calendar: cal) {
                            enabled.insert(bundleID)
                        }
                    case let .offer(want):
                        let offer = SeasonalPrompt.bundleToOffer(
                            bundles: bundles, enabledBundleIDs: enabled, now: now, calendar: cal
                        ) { SeasonalPrompt.isSilenced(bundleID: $0, now: now, defaults: defaults, calendar: cal) }
                        XCTAssertEqual(offer?.id, want, "\(zone): \(a.name), offer at \(step.at)")
                    case let .silenced(bundleID, want):
                        XCTAssertEqual(SeasonalPrompt.isSilenced(bundleID: bundleID, now: now, defaults: defaults, calendar: cal),
                                       want, "\(zone): \(a.name), \(bundleID) at \(step.at)")
                    }
                }
            }
        }
    }

    func testHeadlineAndSettingsNoteInEveryZone() throws {
        let g = try golden()
        let bundles = try shippedBundles()
        for zone in zones(g) {
            let cal = try calendar(zone)
            for c in g.headline {
                let b = try bundle(c.bundle, c.def, in: bundles)
                XCTAssertEqual(SeasonalPrompt.headline(for: b, now: try local(c.at, cal), calendar: cal), c.want, zone)
            }
            for c in g.label {
                let b = try bundle(c.bundle, c.def, in: bundles)
                XCTAssertEqual(b.spotlightLabel(now: try local(c.at, cal), calendar: cal).uppercased(), c.want,
                               "\(zone) \(c.at)")
            }
        }
    }

    /// Negative control: the same vectors over the shipped bundles with TIS THE SEASON's
    /// `seasonStart` removed. Exactly the late November holiday vectors must fail, so the
    /// vectors are what pin the early start, and nothing else moves with it.
    func testNegativeControlWithoutTheEarlyStartOnlyLateNovemberFails() throws {
        let g = try golden()
        let stripped = try shippedBundles().map { b in
            b.id == "tis-the-season"
                ? ChannelBundle(id: b.id, name: b.name, description: b.description, channelIDs: b.channelIDs,
                                activeMonths: b.activeMonths, enabled: b.enabled, seasonStart: nil)
                : b
        }
        let november: (String) -> Bool = { $0.dropFirst(5).hasPrefix("11") }
        let expected = Set(
            g.inSeason.filter { $0.bundle == "tis-the-season" && $0.want && november($0.at) }.map(\.name)
            + g.offer.filter { $0.want == "tis-the-season" && november($0.at) }.map { "offer: \($0.name)" }
            + g.lead.filter { $0.want.contains("tis-the-season") && november($0.at) }.map { "lead: \($0.name)" })
        XCTAssertEqual(expected.count, 10, "the vectors lost their late November cases")
        for zone in zones(g) {
            XCTAssertEqual(Set(try windowFailures(g, bundles: stripped, calendar: try calendar(zone))), expected, zone)
        }
    }
}
