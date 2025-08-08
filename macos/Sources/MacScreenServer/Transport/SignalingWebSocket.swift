import Foundation

@MainActor
public final class SignalingWebSocket: NSObject {
    private var task: URLSessionWebSocketTask?
    private let url: URL
    private let role: String
    public var onMessage: (([String: Any]) -> Void)?

    public init(url: URL, role: String) {
        self.url = url
        self.role = role
    }

    public func connect() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        task?.resume()
        // anuncia o papel (mac)
        send(["type": "hello", "role": role])
        listen()
    }

    public func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func listen() {
        task?.receive { [weak self] result in
            // Esta closure é tratada como @Sendable → saltamos para o MainActor
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let err):
                    print("WS receive error:", err)
                case .success(let msg):
                    switch msg {
                    case .string(let text):
                        if let data = text.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.onMessage?(obj)
                        }
                    case .data(let data):
                        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.onMessage?(obj)
                        }
                    @unknown default: break
                    }
                }
                // voltar a escutar no MainActor
                self.listen()
            }
        }
    }

    public func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { err in
            if let err { print("WS send error:", err) }
        }
    }
}

// A conformance fica @preconcurrency para evitar que o compilador imponha isolamento aqui
extension SignalingWebSocket: @preconcurrency URLSessionWebSocketDelegate {

    // Estes métodos precisam ser 'nonisolated' para satisfazer o protocolo;
    // não acedemos a estado isolado. Usamos a URL do próprio task que vem no parâmetro.
    public nonisolated func urlSession(_ session: URLSession,
                                       webSocketTask: URLSessionWebSocketTask,
                                       didOpenWithProtocol `protocol`: String?) {
        let u = webSocketTask.currentRequest?.url?.absoluteString ?? "(unknown)"
        print("WS connected:", u)
    }

    public nonisolated func urlSession(_ session: URLSession,
                                       webSocketTask: URLSessionWebSocketTask,
                                       didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                                       reason: Data?) {
        print("WS closed:", closeCode.rawValue)
    }
}
