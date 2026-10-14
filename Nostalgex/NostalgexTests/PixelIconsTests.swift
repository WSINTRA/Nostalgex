import XCTest
@testable import Nostalgex

/// Guards the hand-edited pixel grids: a missing palette key or a short row would draw a
/// hole or a ragged edge, and nothing else would notice.
final class PixelIconsTests: XCTestCase {

    private let all: [(String, PixelArt)] = [
        ("star", PixelIcons.star),
        ("popcorn", PixelIcons.popcorn),
        ("tvDinner", PixelIcons.tvDinner),
        ("pizza", PixelIcons.pizza),
    ]

    func testEveryRowIsTheSameWidth() {
        for (name, art) in all {
            XCTAssertGreaterThan(art.height, 0, name)
            for (i, row) in art.rows.enumerated() {
                XCTAssertEqual(row.count, art.width, "\(name) row \(i)")
            }
        }
    }

    func testEveryPixelHasAPaletteColour() {
        for (name, art) in all {
            for (i, row) in art.rows.enumerated() {
                for key in row where key != "." {
                    XCTAssertNotNil(PixelIcons.palette[key], "\(name) row \(i) uses '\(key)'")
                }
            }
        }
    }

    func testPaletteIsSixDigitHex() {
        for (key, hex) in PixelIcons.palette {
            XCTAssertNotNil(hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression), "palette '\(key)'")
        }
    }

    func testEachTipHasItsOwnIcon() {
        let rows = TipProduct.allCases.map { PixelIcons.art(for: $0).rows }
        XCTAssertEqual(Set(rows).count, TipProduct.allCases.count)
        XCTAssertFalse(rows.contains(PixelIcons.star.rows))
    }
}
