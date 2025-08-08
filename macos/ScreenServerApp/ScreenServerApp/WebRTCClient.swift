import Foundation
import WebRTC
import AVFoundation
import CoreMedia

public final class WebRTCClient: NSObject {   // <- herda de NSObject

    private let factory: RTCPeerConnectionFactory
    private var pc: RTCPeerConnection?
    private var videoSource: RTCVideoSource?
    private var videoTrack: RTCVideoTrack?

    public var onLocalSdp: ((RTCSessionDescription) -> Void)?
    public var onLocalIce: ((RTCIceCandidate) -> Void)?
    public var onConnectionState: ((RTCPeerConnectionState) -> Void)?

    public override init() {
        RTCInitializeSSL()

        let encoderFactory = RTCDefaultVideoEncoderFactory()
        encoderFactory.preferredCodec = RTCVideoCodecInfo(name: kRTCVideoCodecH264Name)
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
        super.init()
    }

    deinit {
        RTCCleanupSSL()
    }

    public func start() {
        guard pc == nil else { return }

        let config = RTCConfiguration()
        config.iceServers = [ RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]) ]
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        // cria pc local não opcional
        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        self.pc = pc

        // video source / track
        let src = factory.videoSource()
        self.videoSource = src

        let track = factory.videoTrack(with: src, trackId: "screen")
        self.videoTrack = track

        // usar a variável local 'pc' (não opcional)
        let initDir = RTCRtpTransceiverInit()
        initDir.direction = .sendOnly

        guard let pc = pc, let vTrack = videoTrack else {
            // Se por algum motivo ainda não há pc ou track, não prossegue
            return
        }
        _ = pc.addTransceiver(with: vTrack, init: initDir)

    }

    public func makeOffer() {
        guard let pc else { return }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { [weak self] sdp, err in
            guard let self, let sdp else { return }
            self.pc?.setLocalDescription(sdp) { _ in }
            self.onLocalSdp?(sdp)
        }
    }

    public func setRemote(description: RTCSessionDescription) {
        pc?.setRemoteDescription(description, completionHandler: { _ in })
    }

    public func add(remoteIce: RTCIceCandidate) {
        pc?.add(remoteIce, completionHandler: { error in
            if let error {
                print("Falha ao adicionar ICE candidate: \(error)")
            } else {
                print("ICE candidate adicionado com sucesso")
            }
        })


    }

    /// Empurra um frame vindo do ScreenCaptureKit
    public func push(pixelBuffer pb: CVPixelBuffer, pts: CMTime) {
        guard let src = videoSource else { return }
        let rtcBuf = RTCCVPixelBuffer(pixelBuffer: pb)
        let tsNs = Int64(CMTimeGetSeconds(pts) * 1_000_000_000.0)
        let frame = RTCVideoFrame(buffer: rtcBuf, rotation: ._0, timeStampNs: tsNs)

        let capturer = RTCVideoCapturer(delegate: src)
        src.capturer(capturer, didCapture: frame)
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCClient: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onConnectionState?(newState)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onLocalIce?(candidate)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
