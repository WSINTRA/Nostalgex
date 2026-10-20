import XCTest
@testable import Nostalgex

/// One Metadata item the model cannot read is skipped and logged; the page, the section and
/// the scan go on. A section page used to be one strict decode, so a single bad item ended
/// the whole library load with "Your server returned unexpected data".
final class PlexSkippedItemTests: XCTestCase {

    private func page(_ items: [String]) throws -> (items: [PlexRawItem], report: PlexDecodeReport) {
        let json = #"{"MediaContainer":{"totalSize":\#(items.count),"Metadata":[\#(items.joined(separator: ","))]}}"#
        let report = PlexDecodeReport()
        return (try PlexAPIService.decodeSectionPage(Data(json.utf8), report: report).items, report)
    }

    private let heat = #"{"ratingKey":"101","title":"Heat","duration":10200000,"Media":[{"container":"mp4","Part":[{"key":"/library/parts/1/file.mp4"}]}]}"#
    private let ronin = #"{"ratingKey":"103","title":"Ronin","duration":7320000}"#

    func testOneBrokenItemDropsOnlyThatItem() throws {
        let broken = #"{"ratingKey":"202","title":"Broken","duration":60000,"Media":"not an array"}"#
        let (items, report) = try page([heat, broken, ronin])
        XCTAssertEqual(items.map(\.ratingKey), ["101", "103"])
        XCTAssertEqual(items.first?.bestMedia?.Part?.first?.key, "/library/parts/1/file.mp4", "the items around it are whole")
        let skip = try XCTUnwrap(report.skipped.first)
        XCTAssertEqual(report.skipped.count, 1)
        XCTAssertEqual(skip.ratingKey, "202")
        XCTAssertEqual(skip.path, "MediaContainer.Metadata[1]")
        XCTAssertTrue(skip.reason.contains("MediaContainer.Metadata[1].Media"), skip.reason)

        let lines = report.logLines(context: "/library/sections/1/all?X-Plex-Container-Start=500")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("ratingKey=202") && lines[0].contains("Metadata[1]"), lines[0])
    }

    func testItemsMissingARequiredKeyOrNotObjectsAreSkipped() throws {
        let (items, report) = try page([heat, #"{"ratingKey":"7","duration":60000}"#, #""a string""#, "42", ronin])
        XCTAssertEqual(items.map(\.ratingKey), ["101", "103"])
        XCTAssertEqual(report.skipped.map(\.path), ["MediaContainer.Metadata[1]", "MediaContainer.Metadata[2]", "MediaContainer.Metadata[3]"])
        XCTAssertEqual(report.skipped.first?.ratingKey, "7")
        XCTAssertTrue(report.skipped.first?.reason.contains("missing key 'title'") == true)
    }

    func testCleanPageSkipsAndLogsNothing() throws {
        let (items, report) = try page([heat, ronin])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(report.skipped.isEmpty)
        XCTAssertTrue(report.logLines(context: "x").isEmpty)
    }

    func testAPageThatIsNotAPageStillFails() {
        // Per-item only: a broken container or a body that is not JSON fails as before.
        XCTAssertThrowsError(try PlexAPIService.decodeSectionPage(Data(#"{"MediaContainer":{"Metadata":{"ratingKey":"1"}}}"#.utf8)))
        XCTAssertThrowsError(try PlexAPIService.decodeSectionPage(Data(#"{"MediaContainer":{"Metadata":[{"ratingKey":"1""#.utf8)))
    }
}
