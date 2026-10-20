import XCTest
@testable import Nostalgex

/// Regression tests for fullscreen subtitle language resolution and track matching.
final class SubtitleSelectionLogicTests: XCTestCase {

    // MARK: - resolvedLanguageCode

    func testResolvedLanguage_explicitCode_passesThrough() {
        XCTAssertEqual(
            SubtitleSelectionLogic.resolvedLanguageCode(storedCode: "fr", locale: Locale(identifier: "en_US")),
            "fr"
        )
    }

    func testResolvedLanguage_system_followsLocaleGerman() {
        let de = Locale(identifier: "de_DE")
        XCTAssertEqual(
            SubtitleSelectionLogic.resolvedLanguageCode(storedCode: "__system__", locale: de),
            "de"
        )
    }

    func testResolvedLanguage_system_followsLocaleJapanese() {
        let ja = Locale(identifier: "ja_JP")
        XCTAssertEqual(
            SubtitleSelectionLogic.resolvedLanguageCode(storedCode: "__system__", locale: ja),
            "ja"
        )
    }

    // MARK: - languageTagForComparison

    func testLanguageTag_prefersExtendedTagLowercased() {
        XCTAssertEqual(
            SubtitleSelectionLogic.languageTagForComparison(extendedLanguageTag: "en-US", localeIdentifier: "fr_FR"),
            "en-us"
        )
    }

    func testLanguageTag_fallsBackToLocalePrimaryWhenNoExtended() {
        XCTAssertEqual(
            SubtitleSelectionLogic.languageTagForComparison(extendedLanguageTag: nil, localeIdentifier: "es_ES"),
            "es"
        )
    }

    func testLanguageTag_underscoreLocaleNormalized() {
        XCTAssertEqual(
            SubtitleSelectionLogic.languageTagForComparison(extendedLanguageTag: nil, localeIdentifier: "pt_BR"),
            "pt"
        )
    }

    // MARK: - preferredTrackIndex

    func testPreferredTrackIndex_exactPrimaryMatch() {
        let idx = SubtitleSelectionLogic.preferredTrackIndex(
            tags: [Optional("en"), Optional("es")],
            preferredLowercased: "en"
        )
        XCTAssertEqual(idx, 0)
    }

    func testPreferredTrackIndex_regionVariantMatch() {
        let idx = SubtitleSelectionLogic.preferredTrackIndex(
            tags: [Optional("es"), Optional("en-us")],
            preferredLowercased: "en"
        )
        XCTAssertEqual(idx, 1)
    }

    func testPreferredTrackIndex_fallbackToFirstWhenNoMatch() {
        let idx = SubtitleSelectionLogic.preferredTrackIndex(
            tags: [Optional("de"), Optional("fr")],
            preferredLowercased: "ja"
        )
        XCTAssertEqual(idx, 0)
    }

    func testPreferredTrackIndex_nilTags_fallbackZero() {
        let idx = SubtitleSelectionLogic.preferredTrackIndex(
            tags: [nil, Optional("fr")],
            preferredLowercased: "en"
        )
        XCTAssertEqual(idx, 0)
    }

    // MARK: - shouldAutoEnableSubtitles

    func testShouldAutoEnable_foreignOnlyAudio_true() {
        XCTAssertTrue(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("fr")],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_matchingTrackPresent_false() {
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("fr"), Optional("en")],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_regionVariantMatches_false() {
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("en-us")],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_emptyTags_false() {
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_nilTag_false() {
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [nil],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_undTag_false() {
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("und")],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_undMixedWithKnownForeign_false() {
        // Strict: any unknown tag means we can't be sure there's no match.
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("fr"), Optional("und")],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_caseInsensitive_false() {
        XCTAssertFalse(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("EN")],
            preferredAudioLowercased: "en"
        ))
    }

    func testShouldAutoEnable_multipleForeignTracks_true() {
        XCTAssertTrue(SubtitleSelectionLogic.shouldAutoEnableSubtitles(
            audioTags: [Optional("fr"), Optional("de"), Optional("ja")],
            preferredAudioLowercased: "en"
        ))
    }

    // MARK: - Server language codes against the setting

    func testPrimaryLanguageReadsEveryCodeAServerUses() {
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("eng"), "en")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("EN"), "en")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("en-US"), "en")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("ger"), "de", "bibliographic code, common in MKV")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("deu"), "de", "terminology code, what Jellyfin 12.2 reports")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("fre"), "fr")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("chi"), "zh")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("zh-Hans"), "zh")
        XCTAssertEqual(SubtitleSelectionLogic.primaryLanguage("pt-BR"), "pt")
        for nothing in [nil, "", "und", "zz9"] as [String?] {
            XCTAssertNil(SubtitleSelectionLogic.primaryLanguage(nothing), String(describing: nothing))
        }
    }

    func testSameLanguage() {
        XCTAssertTrue(SubtitleSelectionLogic.sameLanguage("eng", "en"))
        XCTAssertTrue(SubtitleSelectionLogic.sameLanguage("ger", "deu"))
        XCTAssertTrue(SubtitleSelectionLogic.sameLanguage("por", "pt-BR"))
        XCTAssertFalse(SubtitleSelectionLogic.sameLanguage("spa", "en"))
        XCTAssertFalse(SubtitleSelectionLogic.sameLanguage("und", "en"), "unknown never matches")
        XCTAssertFalse(SubtitleSelectionLogic.sameLanguage(nil, "en"))
    }

    func testCurrentSubtitleLanguageFollowsTheSetting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SubtitleSelectionLogicTests.\(UUID().uuidString)"))
        let locale = Locale(identifier: "fr_FR")
        XCTAssertEqual(SubtitleSelectionLogic.currentSubtitleLanguage(defaults: defaults, locale: locale), "fr", "unset follows the device")
        defaults.set("__system__", forKey: SubtitleSelectionLogic.subtitleLanguageDefaultsKey)
        XCTAssertEqual(SubtitleSelectionLogic.currentSubtitleLanguage(defaults: defaults, locale: locale), "fr")
        defaults.set("de", forKey: SubtitleSelectionLogic.subtitleLanguageDefaultsKey)
        XCTAssertEqual(SubtitleSelectionLogic.currentSubtitleLanguage(defaults: defaults, locale: locale), "de")
    }
}
