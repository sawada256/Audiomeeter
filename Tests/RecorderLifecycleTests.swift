import Foundation
import AVFoundation
@main struct RecorderLifecycleTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = AudioRecorderPlayer()
        recorder.recordingFormat = .wavFloat32
        let url = recorder.startRecording(sampleRate: 48000, directory: folder)!
        let samples = [Float](repeating: 0.25, count: 512)
        for _ in 0..<100 { samples.withUnsafeBufferPointer { recorder.pushRecordingFrames(buffer: $0.baseAddress!, frames: 256) } }
        async let first: Void = recorder.finishRecording()
        async let second: Void = recorder.finishRecording()
        _ = await (first, second)
        precondition(!recorder.isRecording && !recorder.isFinalizingRecording)
        let file = try AVAudioFile(forReading: url)
        precondition(file.length == 25_600)
        precondition(recorder.recordingError == nil)
        let next = recorder.startRecording(sampleRate: 48000, directory: folder)!
        await recorder.finishRecording()
        precondition(next != url)
        print("Recorder lifecycle passed: concurrent async stop, complete drain, restart preserves previous file")
    }
}
