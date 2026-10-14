import Foundation

/// Glue between the app and `RatingNudgePolicy`. The rules live in the policy; this
/// only feeds it facts and shows or hides the banner.
extension AppState {

    /// Hands a fresh tracker the callback that counts its watch when it stops.
    func attachRatingNudgeCounter(to tracker: PlaybackTracker) {
        tracker.onStop = { [weak self] tracker, watchedSeconds in
            self?.countViewingSessionIfQualifies(tracker, watchedSeconds: watchedSeconds)
        }
    }

    func noteRatingNudgePlaybackFailure() {
        ratingNudgeLaunch.hadPlaybackFailure = true
    }

    /// The single trigger: the viewer has just left fullscreen for the guide.
    func ratingNudgeGuideDidReturn() {
        // Playback usually carries on in the guide's preview, so the watch that just
        // ended in fullscreen has not stopped yet. Count it now if it is long enough.
        if let tracker = playbackTracker {
            countViewingSessionIfQualifies(tracker, watchedSeconds: tracker.watchedSecondsSoFar)
        }
        let persisted = ratingNudgeStore.persisted
        guard RatingNudgePolicy.shouldShow(persisted: persisted, launch: ratingNudgeLaunch) else { return }
        ratingNudgeLaunch.shownThisLaunch = true
        // Recorded on appearance, so it never repeats this version whatever the choice.
        if !ratingNudgeLaunch.forced {
            ratingNudgeStore.recordShown(version: ratingNudgeLaunch.appVersion)
        }
        print("[Plex90] Rating nudge shown (sessions=\(persisted.qualifyingSessions), version=\(ratingNudgeLaunch.appVersion), forced=\(ratingNudgeLaunch.forced))")
        Analytics.track(.ratingNudgeShown)
        isRatingNudgeVisible = true
        ratingNudgeDismissTask?.cancel()
        ratingNudgeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(RatingNudgePolicy.autoDismissSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissRatingNudge()
        }
    }

    /// RATE: the caller opens the product page.
    func ratingNudgeRateTapped() {
        Analytics.track(.ratingNudgeTapped)
        recordRatingTapped()
        dismissRatingNudge()
    }

    /// Any RATE press (banner or the Settings tile). The banner never shows again and
    /// the Settings tile says thanks.
    func recordRatingTapped() {
        ratingNudgeStore.recordRated()
        hasTappedRate = true
    }

    /// Every way out (NOT NOW, RATE, Up, Menu, the timeout) ends here, and focus goes
    /// back to the live channel row as if the banner had never appeared.
    func dismissRatingNudge() {
        ratingNudgeDismissTask?.cancel()
        ratingNudgeDismissTask = nil
        guard isRatingNudgeVisible else { return }
        isRatingNudgeVisible = false
        if !isFullScreen { guideLiveRowFocusRequest &+= 1 }
    }

    private func countViewingSessionIfQualifies(_ tracker: PlaybackTracker, watchedSeconds: Double) {
        guard !tracker.countedAsViewingSession,
              RatingNudgePolicy.countsAsViewingSession(watchedSeconds: watchedSeconds) else { return }
        tracker.countedAsViewingSession = true
        ratingNudgeStore.recordViewingSession()
        print("[Plex90] Rating nudge: viewing session counted (\(Int(watchedSeconds))s), total=\(ratingNudgeStore.persisted.qualifyingSessions)")
    }
}
