import Foundation
import VideoToolbox
import AVFoundation

@available(macOS 12.3, *)
public final class VTEncoder: @unchecked Sendable {
    private var session: VTCompressionSession?

    public init() {}

    public func configure(width: Int32, height: Int32, bitrate: Int = 8_000_000) throws {
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &s
        )
        guard status == noErr, let session = s else {
            throw NSError(domain: "VTEncoder", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Falha a criar VTCompressionSession (\(status))"])
        }
        self.session = session

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        let br = bitrate as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: br)

        let keyInt = 60 as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyInt)

        VTCompressionSessionPrepareToEncodeFrames(session)

        NotificationCenter.default.addObserver(forName: .screenSampleBuffer, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let obj = note.object else { return }

            // Garante que é mesmo um CMSampleBuffer (CoreFoundation) antes de fazer cast
            let cfObj = obj as CFTypeRef
            guard CFGetTypeID(cfObj) == CMSampleBufferGetTypeID() else { return }

            // Depois do typeID check, o cast é seguro
            let sbuf: CMSampleBuffer = unsafeBitCast(obj, to: CMSampleBuffer.self)

            guard let img = CMSampleBufferGetImageBuffer(sbuf),
                  let session = self.session else { return }

            let pts = CMSampleBufferGetPresentationTimeStamp(sbuf)
            VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: img,
                presentationTimeStamp: pts,
                duration: .invalid,
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )
        }

    }
}
