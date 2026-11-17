import CoreGraphics
import Foundation
import ImageIO
import Observation

/// Streams MJPEG multipart or periodic `/shot.jpg` frames from Android IP Webcam / DroidCam
/// over local Wi-Fi without disturbing USB PTP RAW/DNG tethering.
@MainActor
@Observable
package final class NetworkMJPEGStreamService {
    package var streamURLString: String = "http://192.168.1.50:8080/video"
    package private(set) var isStreaming: Bool = false
    package var statusNote: String?

    private var worker: MJPEGSessionWorker?

    package init() {}

    package func startStream(
        url rawURL: String,
        onFrame: @escaping @MainActor (CGImage) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            onError("Ingresá una URL válida (ej. http://192.168.1.50:8080/video o :4747/video).")
            return
        }

        stopStream()
        isStreaming = true
        statusNote = "Conectando a stream IP (\(url.host ?? "red"))..."

        let newWorker = MJPEGSessionWorker(
            onFrame: { image in
                Task { @MainActor in onFrame(image) }
            },
            onStatus: { note in
                Task { @MainActor [weak self] in
                    self?.statusNote = note
                }
            },
            onFailure: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.stopStream()
                    onError(message)
                }
            }
        )
        worker = newWorker
        newWorker.start(url: url)
    }

    package func stopStream() {
        worker?.stop()
        worker = nil
        isStreaming = false
        statusNote = nil
    }

    /// Extracts the next complete SOI (`FF D8`) ... EOI (`FF D9`) JPEG frame from a rolling byte buffer.
    nonisolated package static func extractNextJPEGFrame(from buffer: inout Data) -> Data? {
        let soi = Data([0xFF, 0xD8])
        let eoi = Data([0xFF, 0xD9])
        guard let startRange = buffer.range(of: soi) else {
            if buffer.count > 1 {
                buffer = Data([buffer[buffer.count - 1]])
            }
            return nil
        }
        let searchStart = startRange.upperBound
        guard searchStart < buffer.endIndex,
              let endRange = buffer.range(of: eoi, options: [], in: searchStart..<buffer.endIndex) else {
            if startRange.lowerBound > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<startRange.lowerBound)
            }
            return nil
        }
        let frame = Data(buffer[startRange.lowerBound..<endRange.upperBound])
        buffer.removeSubrange(buffer.startIndex..<endRange.upperBound)
        return frame
    }
}

private final class MJPEGSessionWorker: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kairosvisuals.photopic.mjpeg")
    private let onFrame: @Sendable (CGImage) -> Void
    private let onStatus: @Sendable (String) -> Void
    private let onFailure: @Sendable (String) -> Void

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var snapshotTask: Task<Void, Never>?
    private var buffer = Data()
    private var isStopped = false

    init(
        onFrame: @escaping @Sendable (CGImage) -> Void,
        onStatus: @escaping @Sendable (String) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) {
        self.onFrame = onFrame
        self.onStatus = onStatus
        self.onFailure = onFailure
    }

    func start(url: URL) {
        queue.async {
            guard !self.isStopped else { return }
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 6
            cfg.timeoutIntervalForResource = 0
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            let urlSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
            self.session = urlSession
            let task = urlSession.dataTask(with: url)
            self.dataTask = task
            task.resume()
        }
    }

    func stop() {
        queue.async {
            self.isStopped = true
            self.snapshotTask?.cancel()
            self.snapshotTask = nil
            self.dataTask?.cancel()
            self.dataTask = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.buffer.removeAll()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            completionHandler(.cancel)
            onFailure("El servidor respondió HTTP \(http.statusCode). Verificá la IP y el puerto.")
            return
        }
        let mime = (response.mimeType ?? "").lowercased()
        let contentType = ((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if mime == "image/jpeg" || (!contentType.contains("multipart") && contentType.contains("image/jpeg")) {
            completionHandler(.cancel)
            if let snapshotURL = response.url ?? dataTask.originalRequest?.url {
                onStatus("Transmitiendo snapshots IP (Wi-Fi)...")
                startSnapshotLoop(url: snapshotURL)
            }
            return
        }
        onStatus("Transmitiendo video IP MJPEG en vivo...")
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async {
            guard !self.isStopped else { return }
            self.buffer.append(data)
            if self.buffer.count > 8_000_000 {
                self.buffer.removeAll()
                return
            }
            while let jpeg = NetworkMJPEGStreamService.extractNextJPEGFrame(from: &self.buffer) {
                if let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
                   let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    self.onFrame(img)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        queue.async {
            guard !self.isStopped, self.snapshotTask == nil, let error else { return }
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }
            self.onFailure("No se pudo conectar al stream Wi-Fi: \(error.localizedDescription)")
        }
    }

    private func startSnapshotLoop(url: URL) {
        queue.async {
            self.snapshotTask?.cancel()
            self.snapshotTask = Task.detached(priority: .userInitiated) { [weak self] in
                while !Task.isCancelled {
                    guard let self, !self.isStopped else { break }
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let src = CGImageSourceCreateWithData(data as CFData, nil),
                       let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        self.onFrame(img)
                    }
                    try? await Task.sleep(for: .milliseconds(90))
                }
            }
        }
    }
}
