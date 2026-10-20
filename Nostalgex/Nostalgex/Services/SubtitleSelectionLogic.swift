import Foundation

/// Pure subtitle preference logic shared by playback (`AppState`) and unit tests.
enum SubtitleSelectionLogic {

    /// Maps stored settings (`__system__` → device locale primary language).
    static func resolvedLanguageCode(storedCode: String, locale: Locale) -> String {
        if storedCode == "__system__" {
            if #available(tvOS 16.0, iOS 16.0, macOS 13.0, watchOS 9.0, *) {
                return locale.language.languageCode?.identifier ?? "en"
            }
            return localeLanguageFallback(locale)
        }
        return storedCode
    }

    private static func localeLanguageFallback(_ locale: Locale) -> String {
        let raw = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if let idx = raw.firstIndex(of: "-") {
            return String(raw[..<idx])
        }
        return raw.isEmpty ? "en" : raw
    }

    /// Builds a comparable language tag from AVFoundation option metadata (matches previous AppState behavior).
    static func languageTagForComparison(extendedLanguageTag: String?, localeIdentifier: String?) -> String? {
        if let ext = extendedLanguageTag, !ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ext.lowercased()
        }
        guard let lid = localeIdentifier else { return nil }
        let raw = lid.replacingOccurrences(of: "_", with: "-").lowercased()
        if let idx = raw.firstIndex(of: "-") {
            return String(raw[..<idx])
        }
        return raw.isEmpty ? nil : raw
    }

    /// True when foreign-audio auto-subtitles should kick in: every audio track's language is
    /// KNOWN and none match the preferred audio language. Any unknown/empty/`und` tag disables
    /// the feature entirely — we can't be sure there is no match, so never guess.
    static func shouldAutoEnableSubtitles(audioTags: [String?], preferredAudioLowercased: String) -> Bool {
        guard !audioTags.isEmpty else { return false }
        for tag in audioTags {
            guard let t = tag?.lowercased(), !t.isEmpty, t != "und" else { return false }
            if t == preferredAudioLowercased || t.hasPrefix(preferredAudioLowercased + "-") { return false }
        }
        return true
    }

    /// Settings key for the subtitle language, shared with `AppState`.
    static let subtitleLanguageDefaultsKey = "nostalgex_subtitle_language"

    /// The subtitle language the viewer chose, resolved the way `AppState` resolves it.
    static func currentSubtitleLanguage(defaults: UserDefaults = .standard, locale: Locale = .current) -> String {
        let stored = defaults.string(forKey: subtitleLanguageDefaultsKey) ?? ""
        return resolvedLanguageCode(storedCode: stored.isEmpty ? "__system__" : stored, locale: locale)
    }

    /// ISO 639-2 gives twenty languages a second, bibliographic code, and Matroska files
    /// often carry it ("ger", "fre"). Foundation knows only the terminology code ("deu").
    private static let bibliographicToTerminology: [String: String] = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
        "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
        "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
        "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    /// The two-letter language of a tag: "eng", "en", "en-US", "ger" and "deu" all reduce to
    /// "en" or "de". Nil for an empty tag, "und", and codes Foundation does not know.
    static func primaryLanguage(_ tag: String?) -> String? {
        guard let raw = tag?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        var code = String(raw.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
        code = bibliographicToTerminology[code] ?? code
        guard !["und", "mul", "zxx", "mis"].contains(code) else { return nil }
        if code.count == 2 { return code }
        return Locale.LanguageCode(code).identifier(.alpha2)
    }

    /// Same language, whichever code each side uses. A server labels tracks "eng"; the
    /// setting says "en". Regions are ignored: a server track has none.
    static func sameLanguage(_ a: String?, _ b: String?) -> Bool {
        guard let x = primaryLanguage(a), let y = primaryLanguage(b) else { return false }
        return x == y
    }

    /// Index of the best option for `preferredLowercased` (BCP‑47 primary or full tag); falls back to `0`.
    static func preferredTrackIndex(tags: [String?], preferredLowercased: String) -> Int {
        let want = preferredLowercased
        if let idx = tags.firstIndex(where: { tag in
            guard let t = tag?.lowercased() else { return false }
            return t == want || t.hasPrefix(want + "-")
        }) {
            return idx
        }
        return 0
    }
}
