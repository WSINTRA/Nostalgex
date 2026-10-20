import Foundation

/// Programmes on one channel that failed in a row, with no picture in between.
///
/// A failed programme shows its card for five seconds and the channel moves on. On a
/// channel where nothing plays (server down, every file in a format the device cannot
/// take) that used to go on for as long as the TV stayed on: a new request to the server
/// and a `playback.error` every five seconds, about 720 an hour with nobody watching.
/// After `limit` failures in a row the channel stops instead, and stays stopped until the
/// viewer tunes, selects the channel again, or the app comes back to the foreground
/// (every one of those goes through `AppState.selectChannel`, which resets the run).
///
/// Why five: one bad encode, or a few bad files next to each other in the schedule, still
/// skip and carry on as before. If even half of a channel's programmes played, five
/// failures in a row would come up by chance about one time in 32 (0.5^5); with four in
/// five playing, about one in 3,000. Five in a row is the server or the device, not bad
/// luck. Getting there takes about 20 seconds when nothing can even be requested (four
/// five-second cards between five failures, measured) and a few minutes on the slowest
/// failure, a 4K server stream that gets 40 seconds before the watchdog gives up. The web
/// tuner stops after three.
///
/// Only a confirmed picture counts as playing (`PlaybackWatchdog.hasPicture` at the
/// startup deadline). Reaching ready is not enough: a file the device opens but cannot
/// decode reaches ready with a black screen, and counting that would let a channel of
/// such files skip forever.
struct ChannelFailureRun: Equatable {
    static let limit = 5

    private(set) var channelID: Int?
    private(set) var count = 0

    /// The channel has hit the limit and should not load anything more.
    var isStopped: Bool { count >= Self.limit }

    /// One more programme on `channelID` failed. Returns true when the channel should stop.
    mutating func recordFailure(onChannel channelID: Int) -> Bool {
        if self.channelID != channelID {
            self.channelID = channelID
            count = 0
        }
        count += 1
        return isStopped
    }

    /// A picture reached the screen, or the viewer chose a channel: start counting again.
    mutating func reset() {
        channelID = nil
        count = 0
    }
}
