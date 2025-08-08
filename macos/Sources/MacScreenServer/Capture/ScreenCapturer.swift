import Foundation
import ScreenCaptureKit
import AVFoundation

public final class ScreenCapturer {
    private var stream: SCStream?
    private let output = SampleBufferStreamOutput()
    private let fps: Int

    public init(fps: Int = 60) {
        self.fps = fps
    }

    public func start() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(domain: "ScreenCapturer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nenhum display disponível"])
        }
        let filter = SCContentFilter(display: display)
        let conf = SCStreamConfiguration()
        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        conf.showsCursor = true
        conf.captureResolution = .automatic

        let stream = SCStream(filter: filter, configuration: conf, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        self.stream = stream
        try await stream.startCapture()
    }

    public func stop() async throws {
        try await stream?.stopCapture()
        stream = nil
    }

    final class SampleBufferStreamOutput: NSObject, SCStreamOutput {
        func stream(_ stream: SCStream, didOutputSampleBuffer sbuf: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, CMSampleBufferIsValid(sbuf) else { return }
            NotificationCenter.default.post(name: .screenSampleBuffer, object: sbuf)
        }
    }
}

public extension Notification.Name {
    static let screenSampleBuffer = Notification.Name("ScreenSampleBuffer")
}
