import Foundation
import os

private final class ByteCounter: Sendable {
    private struct State {
        var session: URLSession?
        var total = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func add(_ count: Int, from session: URLSession) {
        state.withLock { state in
            guard state.session === session else { return }
            state.total += count
        }
    }

    func read() -> Int {
        state.withLock { $0.total }
    }

    func reset(for session: URLSession?) {
        state.withLock { $0 = State(session: session) }
    }
}

@MainActor
final class SpeedTester: NSObject, ObservableObject {
    @Published var mbps: Double = 0
    @Published var peakMbps: Double = 0
    @Published var isRunning = false
    @Published var bytesDownloaded: Int = 0

    private let connections = 6
    private let maxDuration: TimeInterval = 15
    private let retryDelay: Duration = .seconds(1)
    // Cloudflare stalls on requests over ~25 MB.
    private static let chunkBytes = 25_000_000
    private static let chunkURL = URL(string: "https://speed.cloudflare.com/__down?bytes=\(chunkBytes)")!

    private let counter = ByteCounter()
    private var session: URLSession?
    private var sampler: Timer?
    private var startTime = Date()
    private var lastSampleBytes = 0
    private var lastSampleTime = Date()
    private var activity: NSObjectProtocol?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        mbps = 0
        peakMbps = 0
        bytesDownloaded = 0

        // Background menu-bar apps get throttled by App Nap, which starves the
        // download to a trickle. Hold a user-initiated activity for the test.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Running internet speed test")

        let session = makeSession()
        self.session = session
        counter.reset(for: session)
        for _ in 0..<connections { launchTask(on: session) }

        startTime = Date()
        lastSampleBytes = 0
        lastSampleTime = startTime
        startSampler()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sampler?.invalidate()
        sampler = nil
        session?.invalidateAndCancel()
        session = nil
        counter.reset(for: nil)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = connections
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func startSampler() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampler = timer
    }

    private func launchTask(on session: URLSession) {
        session.dataTask(with: Self.chunkURL).resume()
    }

    private func relaunchTask(on session: URLSession, after error: Error?) async {
        if error != nil { try? await Task.sleep(for: retryDelay) }
        guard isRunning, session === self.session else { return }
        launchTask(on: session)
    }

    private func sample() {
        let now = Date()
        let totalBytes = counter.read()
        let deltaBytes = totalBytes - lastSampleBytes
        let deltaTime = now.timeIntervalSince(lastSampleTime)
        lastSampleBytes = totalBytes
        lastSampleTime = now
        bytesDownloaded = totalBytes

        guard deltaTime > 0 else { return }
        let instantMbps = (Double(deltaBytes) * 8.0) / deltaTime / 1_000_000.0
        mbps = mbps == 0 ? instantMbps : (mbps * 0.7 + instantMbps * 0.3)
        peakMbps = max(peakMbps, mbps)

        if now.timeIntervalSince(startTime) >= maxDuration { stop() }
    }
}

extension SpeedTester: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        counter.add(data.count, from: session)
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor [weak self] in
            await self?.relaunchTask(on: session, after: error)
        }
    }
}
