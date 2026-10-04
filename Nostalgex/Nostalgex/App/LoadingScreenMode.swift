import Foundation

/// Which loading screen to show.
///
/// There are three honest situations and they used to share one screen, so a pause with
/// nothing to report still drew the step rail with no steps lit and an empty headline —
/// a progress bar that wasn't measuring anything.
enum LoadingScreenMode: Equatable {
    /// A real first scan: every step, and a warning that it takes a while.
    case firstScan
    /// A later scan or guide rebuild: the same rail, without the first-run warning.
    case update
    /// Busy, but with nothing meaningful to report — reading the Keychain, restoring a
    /// snapshot, or any other short wait. Brand only. Never a progress UI with no progress.
    case splash

    /// `loadingMessage` carries the live headline and is empty until a phase sets one, so
    /// it doubles as "is any real work being narrated right now".
    static func decide(
        didAttemptCredentialHydration: Bool,
        isFirstLibraryLoad: Bool,
        loadingMessage: String,
        scanTotalSections: Int,
        channelBuildTotal: Int
    ) -> LoadingScreenMode {
        // The Keychain read happens before anything is known; there is no scan to narrate.
        guard didAttemptCredentialHydration else { return .splash }

        let narrating = !loadingMessage.trimmingCharacters(in: .whitespaces).isEmpty
        let working = scanTotalSections > 0 || channelBuildTotal > 0
        guard narrating || working else { return .splash }

        return isFirstLibraryLoad ? .firstScan : .update
    }

    var showsStepRail: Bool { self != .splash }
    var showsFirstRunWarning: Bool { self == .firstScan }
}
