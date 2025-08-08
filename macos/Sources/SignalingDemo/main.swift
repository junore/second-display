import Foundation
import MacScreenServer

// 1) Configura o WS para o teu IP/porta
let url = URL(string: "ws://192.168.1.249:8080")!
let ws = SignalingWebSocket(url: url, role: "mac")

// 2) Cria e guarda o WebRTCClient num global simples
Globals.webrtc = WebRTCClient(signaling: ws)

// 3) Arranca a captura de ecrã (60 fps só como exemplo)
let capturer = ScreenCapturer(fps: 60)
Task {
    do {
        try await capturer.start()
        print("Screen capture started")
    } catch {
        print("Screen capture FAILED: \(error)")
    }
}

// 4) Reage a mensagens do Android (quando estiver pronto => negociar)
ws.onMessage = { obj in
    print("MAC <-", obj)
    
    Globals.webrtc?.handleSignaling(obj)

    // Quando a app Android disser que está pronta para receber Offer:
    if let t = obj["type"] as? String, t == "android-ready" {
        Task { await Globals.webrtc?.negotiateOffer() }
    }

    // (Opcional) pings de debug
    if let t = obj["type"] as? String, t == "ping" {
        // nada a fazer
    }
    
}

// Mantém o runloop vivo
RunLoop.main.run()
