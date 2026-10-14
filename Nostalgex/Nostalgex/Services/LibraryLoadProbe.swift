import Foundation

/// Stage markers along the library load, for the big-library harness in NostalgexTests.
///
/// Nil in the app, so each call site costs one lock and a nil check, a dozen times per
/// load. The harness installs a handler to record wall time and memory between marks,
/// which is how a 400k-item library was measured without re-implementing the pipeline.
enum LibraryLoadProbe {
    private static let lock = NSLock()
    private static var _handler: ((String) -> Void)?

    static var handler: ((String) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; lock.unlock() }
    }

    @inline(__always)
    static func mark(_ stage: String) {
        handler?(stage)
    }
}
