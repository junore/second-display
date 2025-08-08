import Foundation
import ScreenCaptureKit
import AVFoundation

@available(macOS 12.3, *)
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
            throw NSError(
                domain: "ScreenCapturer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Nenhum display disponível"]
            )
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let conf = SCStreamConfiguration()
        conf.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        conf.showsCursor = true
        // conf.captureResolution = .automatic // Se quiseres, ativa em macOS 14+

        let stream = SCStream(filter: filter, configuration: conf, delegate: nil)
        try stream.addStreamOutput(
            output,
            type: .screen,
            sampleHandlerQueue: DispatchQueue.global(qos: .userInteractive)
        )
        self.stream = stream
        try await stream.startCapture()
    }

    public func stop() async throws {
        try await stream?.stopCapture()
        stream = nil
    }

    // MARK: - Output
    final class SampleBufferStreamOutput: NSObject, SCStreamOutput {
        func stream(_ stream: SCStream, didOutputSampleBuffer sbuf: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, CMSampleBufferIsValid(sbuf) else { return }

            // Empurra o frame diretamente para o pipeline WebRTC
            if let pb = CMSampleBufferGetImageBuffer(sbuf) {
                Globals.webrtc?.push(pixelBuffer: pb, pts: sbuf.presentationTimeStamp)
            }

            // (Opcional) Se quiseres manter a notificação para debugging paralelo:
            // NotificationCenter.default.post(name: .screenSampleBuffer, object: sbuf)
        }
    }
}

// (Opcional) Mantém a notificação se ainda estiveres a ouvir noutros sítios
public extension Notification.Name {
    static let screenSampleBuffer = Notification.Name("ScreenSampleBuffer")
}
