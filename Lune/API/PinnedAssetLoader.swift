@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// AVPlayer does its own networking and ignores our URLSession delegate, so it
/// can't reach a server whose certificate the user pinned. This loader feeds
/// AVPlayer through `TrustedSession` instead: the asset uses a private URL
/// scheme and AVFoundation asks this delegate for the bytes.
final class PinnedAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private static let scheme = "lune-pinned"
    private static let chunkSize = 512 * 1024

    let asset: AVURLAsset

    private let realURL: URL
    private let fetcher: Fetcher
    private let queue = DispatchQueue(label: "com.sahil.lune.assetloader")
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Returns a loader when `url` is an https URL on a host with a pinned
    /// certificate, otherwise nil and the caller plays the URL directly.
    static func make(for url: URL, session: URLSession = TrustedSession.shared) -> PinnedAssetLoader? {
        guard url.scheme == "https", let host = url.host, ServerTrust.shared.hasPins(for: host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = scheme
        guard let customURL = components.url else { return nil }
        return PinnedAssetLoader(realURL: url, customURL: customURL, session: session)
    }

    private init(realURL: URL, customURL: URL, session: URLSession) {
        self.realURL = realURL
        self.fetcher = Fetcher(url: realURL, session: session)
        self.asset = AVURLAsset(url: customURL)
        super.init()
        asset.resourceLoader.setDelegate(self, queue: queue)
    }

    func invalidate() {
        let running = lock.withLock { () -> [Task<Void, Never>] in
            let all = Array(tasks.values)
            tasks.removeAll()
            return all
        }
        running.forEach { $0.cancel() }
    }

    deinit { invalidate() }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.scheme else { return false }
        let key = ObjectIdentifier(loadingRequest)
        let box = UncheckedSendable(loadingRequest)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.serve(box.value)
                box.value.finishLoading()
            } catch is CancellationError {
                // AVFoundation already cancelled this request.
            } catch {
                box.value.finishLoading(with: error)
            }
            self.lock.withLock { self.tasks[key] = nil }
        }
        lock.withLock { tasks[key] = task }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let task = lock.withLock { tasks.removeValue(forKey: ObjectIdentifier(loadingRequest)) }
        task?.cancel()
    }

    // MARK: - Serving

    private func serve(_ request: AVAssetResourceLoadingRequest) async throws {
        let source = try await fetcher.resolve()

        if let info = request.contentInformationRequest {
            info.contentType = source.contentType
            info.contentLength = source.length
            info.isByteRangeAccessSupported = true
        }

        guard let dataRequest = request.dataRequest else { return }
        var offset = dataRequest.requestedOffset
        let end = dataRequest.requestsAllDataToEndOfResource
            ? source.length
            : min(source.length, offset + Int64(dataRequest.requestedLength))

        while offset < end {
            try Task.checkCancellation()
            let upper = min(end, offset + Int64(Self.chunkSize))
            let data = try await fetcher.read(offset..<upper)
            if data.isEmpty { break }
            dataRequest.respond(with: data)
            offset += Int64(data.count)
        }
    }

    // MARK: - Fetching

    private struct Source: Sendable {
        enum Storage: Sendable {
            case ranged
            case whole(Data)
        }
        let length: Int64
        let contentType: String
        let storage: Storage
    }

    private actor Fetcher {
        let url: URL
        let session: URLSession
        private var resolving: Task<Source, Error>?

        init(url: URL, session: URLSession) {
            self.url = url
            self.session = session
        }

        /// Probes the server once. A 206 means ranged reads work. A 200 means
        /// the server ignored Range (for example while transcoding), so the
        /// body is the whole track and is served from memory.
        func resolve() async throws -> Source {
            if let resolving { return try await resolving.value }
            let url = url, session = session
            let task = Task { () -> Source in
                var request = URLRequest(url: url)
                request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                let type = http.mimeType.flatMap { UTType(mimeType: $0)?.identifier } ?? AVFileType.mp3.rawValue
                switch http.statusCode {
                case 206:
                    guard let total = Self.totalLength(from: http.value(forHTTPHeaderField: "Content-Range")) else {
                        throw URLError(.badServerResponse)
                    }
                    return Source(length: total, contentType: type, storage: .ranged)
                case 200:
                    return Source(length: Int64(data.count), contentType: type, storage: .whole(data))
                default:
                    throw URLError(.badServerResponse)
                }
            }
            resolving = task
            do {
                return try await task.value
            } catch {
                resolving = nil  // don't cache a failed probe
                throw error
            }
        }

        func read(_ range: Range<Int64>) async throws -> Data {
            let source = try await resolve()
            switch source.storage {
            case .whole(let data):
                return data.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
            case .ranged:
                var request = URLRequest(url: url)
                request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 206 else { throw URLError(.badServerResponse) }
                return data
            }
        }

        /// "bytes 0-1/12345" -> 12345
        private static func totalLength(from header: String?) -> Int64? {
            guard let total = header?.split(separator: "/").last else { return nil }
            return Int64(total)
        }
    }
}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
