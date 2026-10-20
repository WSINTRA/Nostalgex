import XCTest
@testable import Nostalgex

/// Plex copies an unmatched file or folder name into `title` (or `summary`) byte for byte.
/// A name written in Latin-1 puts a lone 0xE9 into the JSON, the response is no longer
/// UTF-8, and the whole page fails: "The given data was not valid JSON", NSCocoaErrorDomain
/// 4864, an empty coding path. That is the report this answers: a Plex 1.43.4 library scan
/// stopped halfway through its first section with "Your server returned unexpected data".
///
/// The fixtures are pages a lab Plex Media Server (1.43.4.10903) produced for a synthetic
/// file named `Café Society (2016).mp4` written in Latin-1. Nothing in them comes from a
/// real library.
final class PlexUTF8RepairTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: PlexUTF8RepairTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "\(name).json is not in the test bundle")
        return try Data(contentsOf: url)
    }

    /// The fields 1.0.26 read, decoded the way 1.0.26 decoded them.
    private struct StrictPage: Decodable {
        struct Container: Decodable { let Metadata: [Item]? }
        struct Item: Decodable { let ratingKey: String; let title: String; let summary: String? }
        let MediaContainer: Container
    }

    private func page(_ items: [String]) -> Data {
        Data(#"{"MediaContainer":{"totalSize":\#(items.count),"Metadata":[\#(items.joined(separator: ","))]}}"#.utf8)
    }

    // MARK: - The reported failure

    func testFixturesFailTheStrictDecodeTheWayTheReportDid() throws {
        for name in ["plex-invalid-utf8-minimal", "variant-bad-byte-only-in-title", "variant-bad-byte-in-summary"] {
            XCTAssertThrowsError(try JSONDecoder().decode(StrictPage.self, from: try fixture(name)), name) { error in
                let ns = error as NSError
                XCTAssertEqual(ns.domain, NSCocoaErrorDomain, name)
                XCTAssertEqual(ns.code, 4864, "\(name): the code on the user's error screen")
            }
        }
    }

    func testFailingPagesNowDecodeWithEveryItemKept() throws {
        let cases: [(name: String, title: String, summary: String?, repaired: Int)] = [
            // Title, the file path twice and the two Image alt texts carry the byte.
            ("plex-invalid-utf8-minimal", "Café Society", "", 5),
            ("variant-bad-byte-only-in-title", "Café Society", nil, 1),
            ("variant-bad-byte-in-summary", "Cafe Society", "Sé", 5),
        ]
        for c in cases {
            let report = PlexDecodeReport()
            let decoded = try PlexAPIService.decodeSectionPage(try fixture(c.name), report: report)
            XCTAssertEqual(decoded.totalSize, 1, c.name)
            let item = try XCTUnwrap(decoded.items.first, c.name)
            XCTAssertEqual(decoded.items.count, 1, c.name)
            XCTAssertEqual(item.ratingKey, "74", c.name)
            XCTAssertEqual(item.title, c.title, "\(c.name): the accent is read, not replaced")
            XCTAssertEqual(item.summary, c.summary, c.name)
            XCTAssertEqual(report.repairedBytes, c.repaired, c.name)
            XCTAssertTrue(report.skipped.isEmpty, "\(c.name): nothing skipped: \(report.skipped)")
            XCTAssertEqual(item.bestMedia?.Part?.first?.key, "/library/parts/143/1792164710/file.mp4", c.name)
        }
    }

    func testTheRepairedItemBuildsAPlayableMovie() throws {
        let item = try XCTUnwrap(PlexAPIService.decodeSectionPage(try fixture("plex-invalid-utf8-minimal")).items.first)
        let movie = try XCTUnwrap(PlexAPIService(serverURL: "https://server", token: "t").parseMovieItem(item, isMusicSection: false))
        XCTAssertEqual(movie.title, "Café Society")
        XCTAssertEqual(movie.partKey, "/library/parts/143/1792164710/file.mp4")
        XCTAssertEqual(movie.container, "mp4")
    }

    func testTheRepairLogsOnce() throws {
        let report = PlexDecodeReport()
        _ = try PlexAPIService.decodeSectionPage(try fixture("plex-invalid-utf8-minimal"), report: report)
        let lines = report.logLines(context: "/library/sections/1/all?includeGuids=1&X-Plex-Container-Start=500")
        XCTAssertEqual(lines, ["PLEX UTF-8 /library/sections/1/all?includeGuids=1&X-Plex-Container-Start=500: repaired 5 byte(s) that were not UTF-8, read as Windows-1252"])
    }

    // MARK: - Valid UTF-8 is untouched

    func testValidUTF8PageIsDecodedExactlyAsBefore() throws {
        let data = page([
            #"{"ratingKey":"1","title":"Amélie","summary":"Naïve café, Ångström, Straße"}"#,
            #"{"ratingKey":"2","title":"千と千尋の神隠し","summary":"Emoji 🎬 and a combining e\#u{301}"}"#,
            #"{"ratingKey":"3","title":"Plain ASCII","summary":"é escaped"}"#,
        ])
        XCTAssertNil(PlexUTF8Repair.repair(data), "valid UTF-8 is not copied or changed")

        let report = PlexDecodeReport()
        let decoded = try PlexAPIService.decodeSectionPage(data, report: report)
        let strict = try JSONDecoder().decode(StrictPage.self, from: data).MediaContainer.Metadata ?? []
        XCTAssertEqual(decoded.items.map(\.title), strict.map(\.title))
        XCTAssertEqual(decoded.items.map(\.summary), strict.map(\.summary))
        XCTAssertEqual(decoded.items.map(\.title), ["Amélie", "千と千尋の神隠し", "Plain ASCII"])
        XCTAssertEqual(report.repairedBytes, 0)
        XCTAssertTrue(report.logLines(context: "x").isEmpty)
    }

    func testValidMultibyteSequencesAtEveryLengthAreLeftAlone() {
        // 2, 3 and 4 byte sequences at the edges of what is well formed.
        let samples = ["\u{80}", "\u{7FF}", "\u{800}", "\u{FFFD}", "\u{D7FF}", "\u{E000}", "\u{10000}", "\u{10FFFF}"]
        for s in samples {
            XCTAssertNil(PlexUTF8Repair.repair(Data(#"{"t":"\#(s)"}"#.utf8)), "U+\(String(s.unicodeScalars.first!.value, radix: 16))")
        }
    }

    // MARK: - Mixed

    func testMixedValidUTF8AndStrayBytesKeepBothRight() throws {
        var bytes = Array(#"{"MediaContainer":{"Metadata":[{"ratingKey":"9","title":"Amélie "#.utf8)
        bytes += Array("Caf".utf8) + [0xE9]                          // stray Latin-1 é
        bytes += Array(" 🎬 ".utf8)                                   // valid 4-byte emoji
        bytes += [0x93] + Array("quoted".utf8) + [0x94]              // Windows-1252 curly quotes
        bytes += Array(#"","summary":"naïve "#.utf8) + [0x80] + Array(#"5"}]}}"#.utf8) // € sign
        let data = Data(bytes)
        XCTAssertThrowsError(try JSONDecoder().decode(StrictPage.self, from: data), "the strict decode still fails on this page")

        let report = PlexDecodeReport()
        let item = try XCTUnwrap(PlexAPIService.decodeSectionPage(data, report: report).items.first)
        XCTAssertEqual(item.title, "Amélie Café 🎬 \u{201C}quoted\u{201D}")
        XCTAssertEqual(item.summary, "naïve €5")
        XCTAssertEqual(report.repairedBytes, 4)
    }

    func testMalformedSequencesAreRepairedBytewise() throws {
        // A lead byte cut short by the closing quote, an overlong encoding, and a UTF-16
        // surrogate written as UTF-8. Each byte reads as Windows-1252; the JSON stays valid.
        let cases: [([UInt8], String)] = [
            ([0xC3], "Ã"),
            ([0xC0, 0xAF], "À¯"),
            ([0xED, 0xA0, 0x80], "í\u{A0}€"),
            ([0xE2, 0x82], "â\u{201A}"),
            ([0xF8], "ø"),
        ]
        for (bad, expected) in cases {
            let data = Data(Array(#"{"MediaContainer":{"Metadata":[{"ratingKey":"1","title":"x"#.utf8) + bad + Array(#""}]}}"#.utf8))
            let report = PlexDecodeReport()
            let item = try XCTUnwrap(PlexAPIService.decodeSectionPage(data, report: report).items.first, "\(bad)")
            XCTAssertEqual(item.title, "x" + expected, "\(bad)")
            XCTAssertEqual(report.repairedBytes, bad.count, "\(bad)")
        }
    }

    // MARK: - Mapping

    func testWindows1252MatchesFoundation() {
        let undefined: Set<UInt8> = [0x81, 0x8D, 0x8F, 0x90, 0x9D]
        for byte in UInt8(0x80) ... UInt8(0xFF) where !undefined.contains(byte) {
            let foundation = String(data: Data([byte]), encoding: .windowsCP1252)
            XCTAssertEqual(String(PlexUTF8Repair.windows1252(byte)), foundation, String(byte, radix: 16))
        }
        for byte in undefined {
            XCTAssertEqual(PlexUTF8Repair.windows1252(byte).unicodeScalars.first?.value, UInt32(byte))
        }
    }

    func testPreparedLeavesValidDataAloneAndRepairsTheRest() throws {
        let valid = Data(#"[{"name":"Café Server"}]"#.utf8)
        XCTAssertEqual(PlexUTF8Repair.prepared(valid, context: "test"), valid)
        let invalid = Data(Array(#"[{"name":"Caf"#.utf8) + [0xE9] + Array(#" Server"}]"#.utf8))
        let fixed = PlexUTF8Repair.prepared(invalid, context: "test")
        XCTAssertEqual(String(data: fixed, encoding: .utf8), #"[{"name":"Café Server"}]"#)
    }

    func testSectionsAndCollectionsGoThroughTheRepair() throws {
        let sections = Data(Array(#"{"MediaContainer":{"Directory":[{"key":"1","title":"Pel"#.utf8) + [0xED] + Array(#"culas","type":"movie"}]}}"#.utf8))
        XCTAssertEqual(try PlexAPIService.decodeSections(sections).map(\.title), ["Películas"])
    }
}
