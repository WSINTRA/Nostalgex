import Foundation

/// What the Menu button should do from the guide.
///
/// `onExitCommand` consumes the press whenever a closure is attached — returning early
/// from inside it is not the same as declining it. The first version guarded inside the
/// closure, so once focus was already on the live channel Menu did nothing at all and the
/// app could never be backgrounded. The handler therefore has to be absent, not inert:
/// `.letSystemHandle` means pass `nil` to `onExitCommand(perform:)`.
enum GuideExitAction: Equatable {
    /// Pull focus back to the channel that is playing.
    case jumpToLiveChannel(Int)
    /// Attach no handler, so tvOS does its own thing and the viewer can leave the app.
    case letSystemHandle

    static func decide(liveChannelID: Int?, focusedChannelID: Int?) -> GuideExitAction {
        guard let liveID = liveChannelID, focusedChannelID != liveID else {
            return .letSystemHandle
        }
        return .jumpToLiveChannel(liveID)
    }
}
