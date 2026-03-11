import Foundation

/// Maintains the lightweight history websocket that pushes unread and status changes to the client.
final class FoxHistoryPushClient: NSObject {
    var onEvent: ((HistoryPushEvent) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var socketTask: URLSessionWebSocketTask?
    private lazy var urlSession: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()

    /// Opens the history push socket and starts the recursive receive loop.
    func connect(url: URL, authToken: String?) {
        guard socketTask == nil else { return }
        _ = authToken
        debugLog(.history, "push socket connect \(foxPreview(foxRedactToken(in: url.absoluteString), limit: 180))")
        socketTask = urlSession.webSocketTask(with: url)
        socketTask?.resume()
        receiveNext()
    }

    /// Closes the history push socket and notifies listeners that the connection is offline.
    func disconnect() {
        debugLog(.history, "push socket disconnect")
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        onConnectionChange?(false)
    }

    /// Receives the next websocket message and converts it into a strongly typed history event.
    private func receiveNext() {
        socketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let event = self.decodeEvent(data: data) {
                    self.onEvent?(event)
                }
                self.receiveNext()
            case .success(.data(let data)):
                if let event = self.decodeEvent(data: data) {
                    self.onEvent?(event)
                }
                self.receiveNext()
            case .failure:
                debugLog(.history, "push socket receive failed")
                self.disconnect()
            @unknown default:
                debugLog(.history, "push socket receive unknown event")
                self.disconnect()
            }
        }
    }

    /// Decodes the compact server event payload used by the history push channel.
    private func decodeEvent(data: Data) -> HistoryPushEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawStatus = object["status"] as? String
        return HistoryPushEvent(
            type: object["type"] as? String ?? "unknown",
            sessionId: object["sessionId"] as? String,
            status: rawStatus.flatMap(PracticeSessionStatus.init(rawValue:)),
            processingStage: object["processingStage"] as? String,
            resultVersion: object["resultVersion"] as? Int
        )
    }
}

extension FoxHistoryPushClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onConnectionChange?(true)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        disconnect()
    }
}
