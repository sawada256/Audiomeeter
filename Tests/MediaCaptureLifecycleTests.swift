import AppKit

@main struct MediaCaptureLifecycleTests {
    static func main() {
        let capture = MediaKeyCapture { _ in }
        // The UI thread intentionally does not pump its run loop.
        for _ in 0..<100 {
            if capture.status != .starting { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        precondition(capture.status != .starting, "Capture startup must not wait for the UI run loop")
        let start = Date()
        capture.stop(); capture.stop()
        precondition(Date().timeIntervalSince(start) < 0.05, "Capture stop must not wait for an event-tap thread")
        precondition(capture.status == .stopped)
        for _ in 0..<10 { let pending = MediaKeyCapture { _ in }; pending.stop() }
        print("Capture starts without the UI run loop; shutdown is nonblocking and idempotent")
    }
}
