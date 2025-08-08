import Foundation
import VideoToolbox
import AVFoundation

public final class VTEncoder {
    private var session: VTCompressionSession?

    public init() {}

    public func configure(width: Int32, height: Int32, bitrate: Int = 8_000_000) throws {
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                width: width, height: height,
                                                codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: nil,
                                                imageBufferAttributes: nil,
                                                compressedDataAllocator: nil,
                                                outputCallback: nil,
                                                refcon: nil,
                                                compressionSessionOut: &s)
        guard status == noErr, let session = s else {
            throw NSError(domain: "VTEncoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Falha a criar VTCompressionSession"])
        }
        self.session = session

        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)

        var br = bitrate as CFNumber
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, br)

        var keyInt = 60 as CFNumber
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, keyInt)

        VTCompressionSessionPrepareToEncodeFrames(session)

        NotificationCenter.default.addObserver(forName: .screenSampleBuffer, object: nil, queue: .main) { [weak self] note in
            guard let self, let sbuf = note.object as? CMSampleBuffer,
                  let img = CMSampleBufferGetImageBuffer(sbuf),
                  let session = self.session else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sbuf)
            VTCompressionSessionEncodeFrame(session, imageBuffer: img, presentationTimeStamp: pts,
                                            duration: .invalid, frameProperties: nil, infoFlagsOut: nil)
            // TODO: configurar outputCallback para enviar NALs via transporte
        }
    }
}
