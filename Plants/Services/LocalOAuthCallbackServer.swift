import Foundation
import Network

final class LocalOAuthCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "me.bn4t.plants.oauth-callback")
    private let lock = NSLock()

    private var listener: NWListener?
    private var port: NWEndpoint.Port?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var readyResult: Result<URL, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackResult: Result<URL, Error>?
    private var stopped = false

    func start() async throws -> URL {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            throw OpenRouterConnectionError.callbackServerFailed
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = listener.port else {
                    completeReady(.failure(OpenRouterConnectionError.callbackServerFailed))
                    return
                }
                self.port = port
                let url = URL(string: "http://localhost:\(port.rawValue)/openrouter/callback")!
                completeReady(.success(url))
            case .failed:
                completeReady(.failure(OpenRouterConnectionError.callbackServerFailed))
                fail(with: OpenRouterConnectionError.callbackServerFailed)
            case .cancelled:
                fail(with: OpenRouterConnectionError.cancelled)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveRequest(on: connection, buffer: Data())
        }
        listener.start(queue: queue)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result = readyResult {
                    lock.unlock()
                    continuation.resume(with: result)
                } else if stopped {
                    lock.unlock()
                    continuation.resume(throwing: OpenRouterConnectionError.callbackServerFailed)
                } else {
                    readyContinuation = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.fail(with: CancellationError())
            self.stop()
        }
    }

    func waitForCallback() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result = callbackResult {
                    lock.unlock()
                    continuation.resume(with: result)
                } else if stopped {
                    lock.unlock()
                    continuation.resume(throwing: OpenRouterConnectionError.callbackServerFailed)
                } else {
                    callbackContinuation = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            self.fail(with: CancellationError())
            self.stop()
        }
    }

    func fail(with error: Error) {
        finish(.failure(error))
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let ready = readyContinuation
        readyContinuation = nil
        let callback = callbackContinuation
        callbackContinuation = nil
        let listener = listener
        self.listener = nil
        lock.unlock()

        listener?.cancel()
        ready?.resume(throwing: OpenRouterConnectionError.callbackServerFailed)
        callback?.resume(throwing: OpenRouterConnectionError.cancelled)
    }

    private func completeReady(_ result: Result<URL, Error>) {
        lock.lock()
        guard readyResult == nil else {
            lock.unlock()
            return
        }
        readyResult = result
        let continuation = readyContinuation
        readyContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard callbackResult == nil else {
            lock.unlock()
            return
        }
        callbackResult = result
        let continuation = callbackContinuation
        callbackContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.start(queue: queue)
        readMore(on: connection, buffer: buffer)
    }

    private func readMore(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if accumulated.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete || error != nil {
                handleRequest(accumulated, on: connection)
            } else {
                readMore(on: connection, buffer: accumulated)
            }
        }
    }

    private func handleRequest(_ data: Data, on connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first,
              firstLine.hasPrefix("GET "),
              let target = firstLine.split(separator: " ").dropFirst().first,
              let port,
              let url = URL(string: "http://localhost:\(port.rawValue)\(target)")
        else {
            sendResponse(status: "400 Bad Request", message: "The sign-in callback could not be read.", on: connection)
            return
        }

        guard url.path == "/openrouter/callback" else {
            sendResponse(status: "404 Not Found", message: "Callback not found.", on: connection)
            return
        }

        sendResponse(
            status: "200 OK",
            message: "OpenRouter is connected. You can return to Plants.",
            on: connection
        )
        finish(.success(url))
    }

    private func sendResponse(status: String, message: String, on connection: NWConnection) {
        let escapedMessage = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let body = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:-apple-system;padding:48px 24px;text-align:center}h1{font-size:24px}</style></head>
        <body><h1>Plants</h1><p>\(escapedMessage)</p></body></html>
        """
        let bodyData = Data(body.utf8)
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
