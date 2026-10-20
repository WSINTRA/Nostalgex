import XCTest
@testable import Nostalgex

/// Guards the wire contract for every event Nostalgex sends. If a signal name or
/// parameter shape changes, the corresponding TelemetryDeck dashboard breaks — so
/// these tests exist as much for the dashboard's sake as for the app's.
final class AnalyticsEventTests: XCTestCase {

    // MARK: - Launch and credentials

    func testLaunchCarriesKind() {
        XCTAssertEqual(AnalyticsEvent.launch(kind: .first).name, "app.launch")
        XCTAssertEqual(AnalyticsEvent.launch(kind: .first).parameters, ["kind": "first"])
        XCTAssertEqual(AnalyticsEvent.launch(kind: .returning).parameters, ["kind": "returning"])
    }

    func testCredentialsSignInLostCarriesCodeOnly() {
        let event = AnalyticsEvent.credentialsSignInLost(code: "-25300")
        XCTAssertEqual(event.name, "credentials.sign_in_lost")
        XCTAssertEqual(event.parameters, ["code": "-25300"])
    }

    func testCredentialsPersistFailedHasNoParameters() {
        let event = AnalyticsEvent.credentialsPersistFailed
        XCTAssertEqual(event.name, "credentials.persist_failed")
        XCTAssertTrue(event.parameters.isEmpty)
    }

    // MARK: - Connect

    func testConnectStartedCarriesBackendAndMethod() {
        let event = AnalyticsEvent.connectStarted(backend: .jellyfin, method: .quickConnect)
        XCTAssertEqual(event.name, "connect.started")
        XCTAssertEqual(event.parameters, ["backend": "jellyfin", "method": "quick_connect"])
    }

    func testConnectCompletedSerializesServerCount() {
        let event = AnalyticsEvent.connectCompleted(backend: .plex, serverCount: 3)
        XCTAssertEqual(event.name, "connect.completed")
        XCTAssertEqual(event.parameters, ["backend": "plex", "serverCount": "3"])
    }

    func testConnectFailedCarriesReason() {
        let event = AnalyticsEvent.connectFailed(backend: .emby, reason: "emby_unreachable")
        XCTAssertEqual(event.parameters, ["backend": "emby", "reason": "emby_unreachable"])
    }

    func testConnectCancelledAndCodeExpiredNameTheMethod() {
        let cancelled = AnalyticsEvent.connectCancelled(backend: .plex, method: .pin)
        XCTAssertEqual(cancelled.name, "connect.cancelled")
        XCTAssertEqual(cancelled.parameters["method"], "pin")

        let expired = AnalyticsEvent.connectCodeExpired(backend: .jellyfin, method: .quickConnect)
        XCTAssertEqual(expired.name, "connect.code_expired")
        XCTAssertEqual(expired.parameters["method"], "quick_connect")
    }

    func testServerPickerConfirmedCarriesCount() {
        let event = AnalyticsEvent.connectServerPickerConfirmed(backend: .plex, serverCount: 2)
        XCTAssertEqual(event.name, "connect.server_picker.confirmed")
        XCTAssertEqual(event.parameters, ["backend": "plex", "serverCount": "2"])
    }

    // MARK: - Library

    func testLibraryLoadCompletedIncludesDurationAndPartialFlag() {
        let event = AnalyticsEvent.libraryLoadCompleted(
            channelCount: 42,
            itemCount: 1200,
            background: true,
            durationMs: 15_432,
            partial: true
        )
        XCTAssertEqual(event.name, "library.load.completed")
        XCTAssertEqual(event.parameters, [
            "channelCount": "42",
            "itemCount": "1200",
            "background": "true",
            "durationMs": "15432",
            "partial": "true",
        ])
    }

    func testLibraryLoadAbandonedFlagsUserInitiated() {
        let event = AnalyticsEvent.libraryLoadAbandoned(
            background: false,
            itemsFound: 800,
            userInitiated: true
        )
        XCTAssertEqual(event.name, "library.load.abandoned")
        XCTAssertEqual(event.parameters, [
            "background": "false",
            "itemsFound": "800",
            "userInitiated": "true",
        ])
    }

    func testLibraryLoadEmptyHasNoParameters() {
        XCTAssertEqual(AnalyticsEvent.libraryLoadEmpty.name, "library.load.empty")
        XCTAssertTrue(AnalyticsEvent.libraryLoadEmpty.parameters.isEmpty)
    }

    func testStopWaitingTappedHasNoParameters() {
        XCTAssertEqual(AnalyticsEvent.libraryStopWaitingTapped.name, "library.load.stop_waiting_tapped")
        XCTAssertTrue(AnalyticsEvent.libraryStopWaitingTapped.parameters.isEmpty)
    }

    func testBackgroundRefreshFailedCarriesReason() {
        let event = AnalyticsEvent.libraryRefreshBackgroundFailed(reason: "load_stalled")
        XCTAssertEqual(event.name, "library.refresh.background_failed")
        XCTAssertEqual(event.parameters, ["reason": "load_stalled"])
    }

    // MARK: - Tuning & playback

    /// A convenience static descriptor used by every tuning/playback test below
    /// so they don't repeat the same four fields inline.
    private let staticDescriptor = AnalyticsChannelDescriptor(
        kind: .static,
        channelID: 5,
        channelName: "90S SITCOMS",
        bundle: "nostalgex"
    )
    private let collectionDescriptor = AnalyticsChannelDescriptor(
        kind: .collection,
        channelID: nil,
        channelName: nil,
        bundle: "collections-franchises"
    )

    func testChannelTunedIncludesMethodAndStaticChannelIdentity() {
        let event = AnalyticsEvent.channelTuned(
            channelNumber: 74,
            backend: .plex,
            method: .miniStrip,
            channel: staticDescriptor
        )
        XCTAssertEqual(event.name, "channel.tuned")
        XCTAssertEqual(event.parameters, [
            "channelNumber": "74",
            "backend": "plex",
            "method": "mini_strip",
            "channelType": "static",
            "channelID": "5",
            "channelName": "90S SITCOMS",
            "bundle": "nostalgex",
        ])
    }

    func testChannelTunedForCollectionOmitsChannelIDAndChannelName() {
        let event = AnalyticsEvent.channelTuned(
            channelNumber: 300,
            backend: .plex,
            method: .guide,
            channel: collectionDescriptor
        )
        XCTAssertEqual(event.parameters["channelType"], "collection")
        XCTAssertEqual(event.parameters["bundle"], "collections-franchises")
        XCTAssertNil(event.parameters["channelID"],
            "Collection channels must never send a stable id — it isn't stable across users")
        XCTAssertNil(event.parameters["channelName"],
            "Collection channels must never send a name — it comes from the user's own library")
    }

    func testPlaybackReadyDistinguishesDeliveryModeAndCarriesChannel() {
        let direct = AnalyticsEvent.playbackReady(
            channelNumber: 11, backend: .plex, delivery: .directPlay, channel: staticDescriptor
        )
        XCTAssertEqual(direct.name, "playback.ready")
        XCTAssertEqual(direct.parameters["delivery"], "direct_play")
        XCTAssertEqual(direct.parameters["channelID"], "5")
        XCTAssertEqual(direct.parameters["channelName"], "90S SITCOMS")
        XCTAssertEqual(direct.parameters["bundle"], "nostalgex")

        let transcode = AnalyticsEvent.playbackReady(
            channelNumber: 11, backend: .jellyfin, delivery: .transcode, channel: collectionDescriptor
        )
        XCTAssertEqual(transcode.parameters["delivery"], "transcode")
        XCTAssertEqual(transcode.parameters["channelType"], "collection")
        XCTAssertNil(transcode.parameters["channelName"])
    }

    func testPlaybackStoppedSendsWatchSecondsAsFloatNotParameter() {
        let event = AnalyticsEvent.playbackStopped(
            channelNumber: 42,
            backend: .plex,
            delivery: .directPlay,
            channel: staticDescriptor,
            activeWatchSeconds: 137.5
        )
        XCTAssertEqual(event.name, "playback.stopped")
        // Watch seconds must ride as floatValue so the dashboard can sum it.
        XCTAssertEqual(event.floatValue, 137.5)
        // Must NOT appear in the string parameter dictionary — else it'd be counted twice.
        XCTAssertNil(event.parameters["activeWatchSeconds"])
        XCTAssertEqual(event.parameters, [
            "channelNumber": "42",
            "backend": "plex",
            "delivery": "direct_play",
            "channelType": "static",
            "channelID": "5",
            "channelName": "90S SITCOMS",
            "bundle": "nostalgex",
        ])
    }

    func testPlaybackErrorSerializesCode() {
        let events: [(AnalyticsPlaybackErrorCode, String)] = [
            (.noPlayableSource, "no_playable_source"),
            (.transcodingUnavailable, "transcoding_unavailable"),
            (.playerFailed, "player_failed"),
            (.watchdogSkip, "watchdog_skip"),
            (.stalled, "stalled"),
        ]
        for (code, wire) in events {
            let event = AnalyticsEvent.playbackError(channelNumber: 5, backend: .emby, code: code)
            XCTAssertEqual(event.name, "playback.error")
            XCTAssertEqual(event.parameters["code"], wire, "unexpected wire value for \(code)")
        }
    }

    func testTranscodeFallbackCarriesChannelAndBackend() {
        let event = AnalyticsEvent.playbackTranscodeFallback(channelNumber: 9, backend: .plex)
        XCTAssertEqual(event.name, "playback.transcode_fallback")
        XCTAssertEqual(event.parameters, ["channelNumber": "9", "backend": "plex"])
    }

    // MARK: - Settings and UX

    func testSettingChangedIsPassthrough() {
        let event = AnalyticsEvent.settingChanged(key: "retro_mode", value: "false")
        XCTAssertEqual(event.name, "setting.changed")
        XCTAssertEqual(event.parameters, ["key": "retro_mode", "value": "false"])
    }

    func testRateTappedHasNoParameters() {
        XCTAssertEqual(AnalyticsEvent.rateTapped.name, "rate.tapped")
        XCTAssertTrue(AnalyticsEvent.rateTapped.parameters.isEmpty)
    }

    // MARK: - Vocabulary safety

    func testBackendRawValueIsStableWire() {
        XCTAssertEqual(AnalyticsBackend.plex.rawValue, "plex")
        XCTAssertEqual(AnalyticsBackend.jellyfin.rawValue, "jellyfin")
        XCTAssertEqual(AnalyticsBackend.emby.rawValue, "emby")
        XCTAssertEqual(AnalyticsBackend.demo.rawValue, "demo")
    }

    func testWireValuesAreLowercaseAndUnderscored() {
        // Regressions here would silently split the dashboard series in two.
        XCTAssertEqual(AnalyticsConnectMethod.quickConnect.wireValue, "quick_connect")
        XCTAssertEqual(AnalyticsTuneMethod.miniStrip.wireValue, "mini_strip")
        XCTAssertEqual(AnalyticsPlaybackDelivery.directPlay.wireValue, "direct_play")
    }

    // MARK: - Only duration-carrying events produce a floatValue

    func testOnlyDurationCarryingEventsProduceFloatValue() {
        // Guard rail: nothing else in the catalog should quietly start using the
        // floatValue channel. It is reserved for accumulated durations.
        XCTAssertNil(AnalyticsEvent.launch(kind: .first).floatValue)
        XCTAssertNil(AnalyticsEvent.connectStarted(backend: .plex, method: .pin).floatValue)
        XCTAssertNil(AnalyticsEvent.libraryLoadCompleted(
            channelCount: 1, itemCount: 1, background: false, durationMs: 1, partial: false
        ).floatValue)
        XCTAssertNil(AnalyticsEvent.playbackReady(
            channelNumber: 1, backend: .plex, delivery: .directPlay, channel: staticDescriptor
        ).floatValue)
        XCTAssertEqual(AnalyticsEvent.playbackStopped(
            channelNumber: 1, backend: .plex, delivery: .directPlay,
            channel: staticDescriptor, activeWatchSeconds: 42
        ).floatValue, 42)
        XCTAssertEqual(AnalyticsEvent.sessionEnded(activeSeconds: 900).floatValue, 900)
    }

    // MARK: - Session length envelope

    func testSessionEndedSendsSecondsAsFloatValue() {
        let event = AnalyticsEvent.sessionEnded(activeSeconds: 1234.5)
        XCTAssertEqual(event.name, "app.session.ended")
        XCTAssertEqual(event.floatValue, 1234.5)
        // Duration must NOT ride in the string parameter dictionary.
        XCTAssertNil(event.parameters["activeSeconds"])
        XCTAssertTrue(event.parameters.isEmpty)
    }
}

// MARK: - AnalyticsChannelDescriptor

/// Discrimination rule + wire-format for the cross-user-comparable channel
/// identity. Uses real Channel constructor calls so the test stays honest to
/// how `materializeCollectionChannels` and `channels.json` actually shape
/// channels at runtime.
///
/// The `staticNameLookup` argument is injected on every call so tests don't
/// depend on the test bundle carrying the app's `channels.json`. In
/// production the default is `BundledChannelNames.name(forStaticChannelID:)`
/// which reads only from the app bundle.
final class AnalyticsChannelDescriptorTests: XCTestCase {

    /// Stub lookup that mimics the bundled `channels.json` for a small set
    /// of ids. Ids not in the dictionary return `nil`, same shape as the
    /// production lookup for unknown ids.
    private let bundledNames: [Int: String] = [
        5: "90S SITCOMS",
        100: "FRANCHISE CHANNEL",
        42: "ARTHOUSE ONE",
    ]
    private func lookup(_ id: Int) -> String? { bundledNames[id] }

    private func staticChannel(id: Int, category: String?, runtimeName: String = "TEST") -> Channel {
        Channel(
            id: id,
            number: id,
            name: runtimeName,     // deliberately arbitrary — must NOT reach the wire
            color: .blue,
            category: category,
            rules: ChannelRules(),
            timeRestrictions: nil,
            minItems: 0
        )
    }

    /// Dynamic collection channels are created with `rules: nil` and
    /// `category` set to a `CollectionCategory` raw value — that's the exact
    /// shape the descriptor keys off.
    private func collectionChannel(id: Int, category: CollectionCategory) -> Channel {
        Channel(
            id: id,
            number: id,
            name: "USER'S BATMAN COLLECTION",  // never sent
            color: .red,
            category: category.rawValue,
            rules: nil,
            timeRestrictions: nil,
            minItems: 0
        )
    }

    func testStaticChannelCarriesIDBundleAndBundledName() {
        let desc = AnalyticsChannelDescriptor.describe(
            staticChannel(id: 5, category: "nostalgex"),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.kind, .static)
        XCTAssertEqual(desc.channelID, 5)
        XCTAssertEqual(desc.channelName, "90S SITCOMS")
        XCTAssertEqual(desc.bundle, "nostalgex")
        XCTAssertEqual(desc.wireParameters, [
            "channelType": "static",
            "channelID": "5",
            "channelName": "90S SITCOMS",
            "bundle": "nostalgex",
        ])
    }

    /// The whole reason we look up the name from the bundle instead of
    /// reading `channel.name` at runtime: `channel.name` can come from a
    /// server-hosted `channels.json` override (see
    /// `AppState.loadChannelConfig()`), which is user-controlled data.
    /// Analytics must always send the bundled name for the id, never
    /// whatever the runtime Channel currently carries.
    func testStaticChannelNameComesFromBundleNotRuntimeName() {
        let desc = AnalyticsChannelDescriptor.describe(
            staticChannel(id: 5, category: "nostalgex", runtimeName: "USER OVERRIDE"),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.channelName, "90S SITCOMS",
            "Runtime Channel.name must never influence the wire name")
        XCTAssertNotEqual(desc.channelName, "USER OVERRIDE")
    }

    /// A static id that isn't in the app-bundled catalog (e.g. a server-
    /// hosted channels.json added a new id) omits channelName rather than
    /// falling back to the runtime Channel.name. Better to skip the wire
    /// key than to leak a user-controlled string.
    func testStaticChannelWithUnknownBundleIdOmitsChannelName() {
        let desc = AnalyticsChannelDescriptor.describe(
            staticChannel(id: 9_999, category: "nostalgex", runtimeName: "SERVER ONLY"),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.kind, .static)
        XCTAssertEqual(desc.channelID, 9_999)
        XCTAssertNil(desc.channelName)
        XCTAssertEqual(desc.wireParameters, [
            "channelType": "static",
            "channelID": "9999",
            "bundle": "nostalgex",
        ])
    }

    func testCollectionChannelOmitsIDAndChannelNameAndUsesCollectionsPrefixedBundle() {
        let desc = AnalyticsChannelDescriptor.describe(
            collectionChannel(id: 221, category: .franchises),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.kind, .collection)
        XCTAssertNil(desc.channelID)
        XCTAssertNil(desc.channelName,
            "Collection channels must never send a name — that's a user-provided string")
        XCTAssertEqual(desc.bundle, "collections-franchises")
        XCTAssertEqual(desc.wireParameters, [
            "channelType": "collection",
            "bundle": "collections-franchises",
        ])
    }

    /// Belt-and-braces: even if a test lookup returned SOMETHING for a
    /// collection channel's id, the descriptor must still omit channelName.
    /// The rule is "kind == collection ⇒ no name", not "no name in the map".
    func testCollectionChannelIgnoresNameLookupEntirely() {
        let alwaysReturns: (Int) -> String? = { _ in "NEVER SEND THIS" }
        let desc = AnalyticsChannelDescriptor.describe(
            collectionChannel(id: 221, category: .franchises),
            staticNameLookup: alwaysReturns
        )
        XCTAssertNil(desc.channelName)
    }

    /// The legacy static category `franchise` (singular) must NOT be mistaken
    /// for the dynamic `franchises` (plural) CollectionCategory. If this ever
    /// flips, static franchise channel ids would silently start reading as
    /// per-user collection ids.
    func testStaticFranchiseCategoryIsNotMisclassifiedAsCollection() {
        let desc = AnalyticsChannelDescriptor.describe(
            staticChannel(id: 100, category: "franchise"),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.kind, .static)
        XCTAssertEqual(desc.channelID, 100)
        XCTAssertEqual(desc.channelName, "FRANCHISE CHANNEL")
        XCTAssertEqual(desc.bundle, "franchise")
    }

    /// A channel missing a category should still send something serializable —
    /// falls back to a fixed sentinel rather than crashing or dropping the key.
    func testStaticChannelWithoutCategoryFallsBackToSentinelBundle() {
        let desc = AnalyticsChannelDescriptor.describe(
            staticChannel(id: 999, category: nil),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.kind, .static)
        XCTAssertEqual(desc.bundle, "uncategorized")
    }

    /// Belt-and-braces: a hypothetical future static channel whose category
    /// happens to string-match a CollectionCategory raw value must still be
    /// classified as static as long as it has rules. Guards against a schema
    /// collision silently reshuffling analytics identity.
    func testStaticChannelWithRulesButCollisionCategoryStaysStatic() {
        let desc = AnalyticsChannelDescriptor.describe(
            staticChannel(id: 42, category: CollectionCategory.custom.rawValue),
            staticNameLookup: lookup
        )
        XCTAssertEqual(desc.kind, .static)
        XCTAssertEqual(desc.channelID, 42)
        XCTAssertEqual(desc.channelName, "ARTHOUSE ONE")
    }
}

// MARK: - Analytics wrapper (demo context)

/// Small fake for capturing the parameters the wrapper hands the transport, so the
/// `demo` context flag can be verified without linking TelemetryDeck.
private final class SpyAnalyticsService: AnalyticsService, @unchecked Sendable {
    struct Call: Equatable {
        let name: String
        let parameters: [String: String]
    }
    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }
    func configure() {}
    func track(_ event: AnalyticsEvent, contextParameters: [String: String]) {
        var params = contextParameters
        for (key, value) in event.parameters { params[key] = value }
        lock.lock()
        _calls.append(Call(name: event.name, parameters: params))
        lock.unlock()
    }
}

final class AnalyticsWrapperTests: XCTestCase {
    /// The wrapper tags every signal with `demo=true|false` from its own context, so
    /// AppState only has to flip a single switch when entering / leaving demo mode.
    func testDemoContextRidesOnEverySignal() {
        let spy = SpyAnalyticsService()
        // No gate: this checks the context flag, not the budget (the gate would hold
        // back the second identical rate.tapped).
        Analytics.configure(with: spy, gate: nil)
        defer {
            Analytics.setDemoMode(false)
            Analytics.configure(with: NoOpAnalytics())
        }

        Analytics.setDemoMode(false)
        Analytics.track(.rateTapped)
        Analytics.setDemoMode(true)
        Analytics.track(.rateTapped)

        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(spy.calls[0].parameters["demo"], "false")
        XCTAssertEqual(spy.calls[1].parameters["demo"], "true")
    }
}

// The Settings update-emails QR: one fixed-vocabulary signal, nothing else.
final class SignupQRSignalTests: XCTestCase {
    func testSettingsQRSignalWireContract() {
        let event = AnalyticsEvent.signupQRShown(backend: .jellyfin)
        XCTAssertEqual(event.name, "signup.qr.shown")
        XCTAssertEqual(event.parameters, ["placement": "settings", "backend": "jellyfin"])
        XCTAssertNil(event.floatValue)
    }
}
