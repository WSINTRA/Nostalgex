import Foundation

// What a Plex response needs before and during decoding so one item cannot fail a library.

/// Plex copies a file or folder name into its JSON byte for byte. An unmatched item whose
/// name was written in Latin-1 (an é stored as the single byte 0xE9) puts that byte into
/// `title` or `summary`, and the response is no longer UTF-8. JSONDecoder refuses it with
/// "The given data was not valid JSON" (NSCocoaErrorDomain 4864, underlying 3840), an empty
/// coding path, and nothing to say which item. Measured on Plex Media Server 1.43.4.10903
/// and 1.42.2.10156.
///
/// The repair reads each byte that is not part of a well-formed UTF-8 sequence as
/// Windows-1252, the superset of Latin-1 such names are written in, so 0xE9 becomes é and
/// the title reads "Café Society". Every well-formed sequence, ASCII or multi-byte, is
/// copied as it is. A stray byte is always 0x80 or above, so the repair can never add a
/// quote, a backslash or a control character to the JSON around it.
enum PlexUTF8Repair {
    /// Nil when `data` is already valid UTF-8, which is every normal response: those are
    /// decoded untouched. Otherwise the repaired copy and how many bytes were replaced.
    static func repair(_ data: Data) -> (data: Data, repairedBytes: Int)? {
        data.withUnsafeBytes { raw -> (Data, Int)? in
            guard let first = firstInvalidIndex(raw), let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            var out = Data(capacity: raw.count + 64)
            out.append(base, count: first)
            var i = first, runStart = first, repaired = 0
            while i < raw.count {
                let length = sequenceLength(raw, at: i)
                if length > 0 { i += length; continue }
                out.append(base + runStart, count: i - runStart)
                out.append(contentsOf: Array(String(windows1252(raw[i])).utf8))
                repaired += 1
                i += 1
                runStart = i
            }
            out.append(base + runStart, count: raw.count - runStart)
            return (out, repaired)
        }
    }

    /// `data` ready to decode, logging one line when anything was repaired. For the Plex
    /// reads that do not go through `PlexAPIService.decodeRepaired` (plex.tv resources,
    /// Continue Watching).
    static func prepared(_ data: Data, context: String) -> Data {
        guard let fixed = repair(data) else { return data }
        InstallDiagnostics.note(logLine(context: context, repairedBytes: fixed.repairedBytes))
        return fixed.data
    }

    static func logLine(context: String, repairedBytes: Int) -> String {
        "PLEX UTF-8 \(context): repaired \(repairedBytes) byte(s) that were not UTF-8, read as Windows-1252"
    }

    /// Index of the first byte that does not start a well-formed UTF-8 sequence.
    static func firstInvalidIndex(_ raw: UnsafeRawBufferPointer) -> Int? {
        let n = raw.count
        var i = 0
        while i < n {
            // ASCII, which is nearly all of a Plex response, eight bytes at a time.
            while i + 8 <= n, raw.loadUnaligned(fromByteOffset: i, as: UInt64.self) & 0x8080_8080_8080_8080 == 0 {
                i += 8
            }
            guard i < n else { return nil }
            let length = sequenceLength(raw, at: i)
            if length == 0 { return i }
            i += length
        }
        return nil
    }

    /// Length of the well-formed UTF-8 sequence that starts at `i` (Unicode table 3-7), or 0.
    static func sequenceLength(_ raw: UnsafeRawBufferPointer, at i: Int) -> Int {
        let b0 = raw[i]
        if b0 < 0x80 { return 1 }
        let n = raw.count
        func continuation(_ k: Int, _ low: UInt8 = 0x80, _ high: UInt8 = 0xBF) -> Bool {
            i + k < n && raw[i + k] >= low && raw[i + k] <= high
        }
        switch b0 {
        case 0xC2 ... 0xDF: return continuation(1) ? 2 : 0
        case 0xE0: return continuation(1, 0xA0) && continuation(2) ? 3 : 0
        case 0xE1 ... 0xEC, 0xEE ... 0xEF: return continuation(1) && continuation(2) ? 3 : 0
        case 0xED: return continuation(1, 0x80, 0x9F) && continuation(2) ? 3 : 0
        case 0xF0: return continuation(1, 0x90) && continuation(2) && continuation(3) ? 4 : 0
        case 0xF1 ... 0xF3: return continuation(1) && continuation(2) && continuation(3) ? 4 : 0
        case 0xF4: return continuation(1, 0x80, 0x8F) && continuation(2) && continuation(3) ? 4 : 0
        default: return 0
        }
    }

    /// Windows-1252. 0xA0 to 0xFF match Latin-1; 0x80 to 0x9F hold the curly quotes, dashes,
    /// the euro sign and the rest. The five bytes Windows-1252 leaves undefined keep their
    /// Latin-1 code point, as browsers do.
    static func windows1252(_ byte: UInt8) -> Character {
        let high: [UInt32] = [
            0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
            0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
            0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
            0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
        ]
        let value = (0x80 ... 0x9F).contains(byte) ? high[Int(byte - 0x80)] : UInt32(byte)
        return Character(Unicode.Scalar(value)!)
    }
}

/// What decoding one Plex response repaired or skipped, for the log.
final class PlexDecodeReport: @unchecked Sendable {
    struct Skip: Equatable {
        let ratingKey: String?
        let path: String
        let reason: String
    }

    private(set) var skipped: [Skip] = []
    /// Bytes that were not UTF-8 and were read as Windows-1252 before decoding.
    var repairedBytes = 0

    static func from(_ decoder: Decoder) -> PlexDecodeReport? {
        decoder.userInfo[.plexDecodeReport] as? PlexDecodeReport
    }

    func skip(ratingKey: String?, codingPath: [CodingKey], error: Error) {
        skipped.append(Skip(ratingKey: ratingKey, path: Self.format(codingPath), reason: Self.describe(error)))
    }

    /// One line for a repair, one per skipped item. Empty for a normal response.
    func logLines(context: String, limit: Int = 12) -> [String] {
        var lines: [String] = []
        if repairedBytes > 0 { lines.append(PlexUTF8Repair.logLine(context: context, repairedBytes: repairedBytes)) }
        for s in skipped.prefix(limit) {
            lines.append("PLEX DECODE \(context): skipped item ratingKey=\(s.ratingKey ?? "?") at \(s.path): \(s.reason)")
        }
        if skipped.count > limit { lines.append("PLEX DECODE \(context): \(skipped.count - limit) more items skipped") }
        return lines
    }

    /// `MediaContainer.Metadata[237].Media[0].bitrate`
    static func format(_ path: [CodingKey]) -> String {
        var out = ""
        for key in path {
            if let i = key.intValue { out += "[\(i)]" } else { out += out.isEmpty ? key.stringValue : ".\(key.stringValue)" }
        }
        return out
    }

    /// The reason with the full path of the field that failed, which is deeper than the item.
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        switch error {
        case .typeMismatch(let type, let ctx): return "expected \(type) at \(format(ctx.codingPath))"
        case .valueNotFound(let type, let ctx): return "null where \(type) was expected at \(format(ctx.codingPath))"
        case .keyNotFound(let key, let ctx): return "missing key '\(key.stringValue)' at \(format(ctx.codingPath))"
        case .dataCorrupted(let ctx): return "corrupt value at \(format(ctx.codingPath)): \(ctx.debugDescription)"
        @unknown default: return String(describing: error)
        }
    }
}

extension CodingUserInfoKey {
    static let plexDecodeReport = CodingUserInfoKey(rawValue: "com.muellhaus.nostalgex.plexDecodeReport")!
}

/// One Metadata item that never fails its page. A section page used to be one strict
/// decode, so a single item the model could not read failed the page, the section and the
/// whole scan. Now that item is nil, logged with its ratingKey and the path of the field
/// that failed, and the items after it still decode: decoding a wrapper that always
/// succeeds keeps the array's cursor moving.
struct PlexSkippableItem<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
        } catch {
            value = nil
            let key = try? KeyProbe(from: decoder).ratingKey
            PlexDecodeReport.from(decoder)?.skip(ratingKey: key ?? nil, codingPath: decoder.codingPath, error: error)
        }
    }

    private struct KeyProbe: Decodable { let ratingKey: String? }
}
