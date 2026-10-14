import SwiftUI

// MARK: - Pixel icons
//
// The four SUPPORT NOSTALGEX tiles draw their icons from the grids below. Each icon is a
// list of rows, one character per pixel, and every character is a key in `palette`.
// A "." is an empty pixel. To swap in new artwork, replace the rows (any size works, the
// renderer scales to whole pixels) and add colours to the palette if you need them.

struct PixelArt {
    let rows: [String]

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }
}

enum PixelIcons {
    /// One palette for every icon. Brand colours first, then the food.
    static let palette: [Character: String] = [
        "Y": "#FFE500",  // brand yellow
        "O": "#FFB020",  // amber, the shade under yellow
        "S": "#FFF7B0",  // pale yellow highlight
        "W": "#FFFFFF",
        "C": "#FFF0C8",  // popcorn cream
        "R": "#FF2244",  // guide red
        "r": "#B3122E",  // red in shadow
        "P": "#FF2DB4",  // brand pink
        "K": "#00D4FF",  // brand cyan
        "k": "#0084B8",  // cyan in shadow
        "B": "#E8963A",  // pizza crust
        "b": "#A85A1C",  // crust edge
        "G": "#AEBCCC",  // foil tray
        "g": "#5D6A80",  // foil edge
        "M": "#9A5230",  // salisbury steak
        "m": "#5E2C16",  // gravy
        "L": "#5BE36B",  // peas
        "l": "#1E8E3E",  // peas in shadow
    ]

    static let star = PixelArt(rows: [
        "................",
        ".......YO.......",
        ".......YO.......",
        "......YYYO......",
        "......YSYO......",
        ".....YSYYYO.....",
        "YYYYYYSYYYYYYYYO",
        ".YYYYYYYYYYYYYO.",
        "..YYYYYYYYYYYO..",
        "...YYYYYYYYYO...",
        "....YYYYYYYO....",
        "...YYYYYYYYYO...",
        "...YYYO..YYYO...",
        "..YYYO....YYYO..",
        "..YYO......YYO..",
        ".YO..........YO.",
    ])

    static let popcorn = PixelArt(rows: [
        "....CC...CC.....",
        "..CCCCO.CCCCO...",
        ".CCYCCOCCCCYCCO.",
        ".COCCCYCCOCCCCC.",
        "CCCOCCCCCOCCCCOC",
        ".RRRRRRRRRRRRRr.",
        ".RRWWRRWWRRWWRr.",
        ".RRWWRRWWRRWWRr.",
        "..RWWRRWWRRWWr..",
        "..RWWRRWWRRWWr..",
        "..RWWRRWWRRWWr..",
        "...WWRRWWRRWG...",
        "...WWRRWWRRWG...",
        "...WWRRWWRRWG...",
        "....WRRWWRRG....",
        "....WRRWWRRG....",
    ])

    static let tvDinner = PixelArt(rows: [
        "................",
        "................",
        ".gggggggggggggg.",
        "gGGGGGGGGGGGGGGg",
        "gGMMMMMMMGLlLLGg",
        "gGMmmMMmMGlLlLGg",
        "gGMMMmmMMGLLlLGg",
        "gGMmMMMmMGGGGGGg",
        "gGGGGGGGGGYOYYGg",
        "gGCWCCCCCGOYYOGg",
        "gGCCCmmCCGYYOYGg",
        "gGCCmmmCCGYOYYGg",
        "gGGGGGGGGGGGGGGg",
        ".gggggggggggggg.",
        "................",
        "................",
    ])

    static let pizza = PixelArt(rows: [
        "..bbbbbbbbbbbb..",
        ".bBBBBBBBBBBBBb.",
        ".bBBBBBBBBBBBBb.",
        ".YYYYYYYYYYYYYO.",
        ".YYYRRYYYYRRYYO.",
        "..YRRRrYYRRRrO..",
        "..YRRrrYYRRrrO..",
        "...YrrYYYYrrO...",
        "...YYYYYYYYYO...",
        "....YYYRRYYO....",
        "....YYRRRrYO....",
        ".....YRRrrO.....",
        ".....YYrrYO.....",
        "......YYYO......",
        "......YYYO......",
        ".......YO.......",
    ])

    static func art(for tip: TipProduct) -> PixelArt {
        switch tip {
        case .popcorn: return popcorn
        case .tvDinner: return tvDinner
        case .pizzaNight: return pizza
        }
    }
}

/// Draws a PixelArt with square, hard-edged pixels. The pixel size is rounded down to a
/// whole point so every pixel lands on the same grid and nothing blurs between them.
struct PixelIconView: View {
    let art: PixelArt
    var size: CGFloat = 96

    var body: some View {
        Canvas { context, canvasSize in
            guard art.width > 0, art.height > 0 else { return }
            let cell = max(1, floor(min(canvasSize.width / CGFloat(art.width),
                                        canvasSize.height / CGFloat(art.height))))
            let originX = floor((canvasSize.width - cell * CGFloat(art.width)) / 2)
            let originY = floor((canvasSize.height - cell * CGFloat(art.height)) / 2)
            let style = FillStyle(antialiased: false)

            for (y, row) in art.rows.enumerated() {
                let pixels = Array(row)
                var x = 0
                while x < pixels.count {
                    let key = pixels[x]
                    // Merge a run of the same colour into one rect.
                    var end = x + 1
                    while end < pixels.count, pixels[end] == key { end += 1 }
                    if key != ".", let hex = PixelIcons.palette[key] {
                        let rect = CGRect(
                            x: originX + CGFloat(x) * cell,
                            y: originY + CGFloat(y) * cell,
                            width: CGFloat(end - x) * cell,
                            height: cell
                        )
                        context.fill(Path(rect), with: .color(Color(hex: hex)), style: style)
                    }
                    x = end
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
