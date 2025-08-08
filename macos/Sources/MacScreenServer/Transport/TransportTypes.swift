import Foundation
import CoreMedia   // <- adiciona isto

public protocol VideoSender {
    func sendH264(nal: Data, isKeyframe: Bool, pts: CMTime)
}

public protocol InputReceiver {
    func onInput(json: String)
}

// Mantemos simples: 'type' mutável com default para não chatear o Codable
public struct FrameMeta: Codable {
    public var type: String = "frame"
    public let ts: Double
    public let w: Int
    public let h: Int
    public let fps: Int
    public let k: Bool
}
