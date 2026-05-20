import Foundation

/// Thumbnail cache loading coordinator (Plan C Phase 2.3).
///
/// Responsibilities:
/// - return cache hits without consuming generation concurrency;
/// - coalesce same-photo misses into one in-flight generation task;
/// - cap distinct miss generation work to `concurrencyLimit`.
actor ThumbnailCoordinator {
    private let concurrencyLimit: Int
    private let shortSidePixels: Int
    private let generate: @Sendable (Data, Int) async throws -> Data

    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var inFlight: [UUID: Task<Data, Swift.Error>] = [:]

    init(
        concurrencyLimit: Int = 4,
        shortSidePixels: Int = 1_200,
        generate: @escaping @Sendable (Data, Int) async throws -> Data = { data, pixels in
            try ThumbnailGenerator.generate(from: data, shortSidePixels: pixels)
        }
    ) {
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.shortSidePixels = shortSidePixels
        self.generate = generate
    }

    func loadThumbnailData(
        id: UUID,
        readCached: @Sendable () throws -> Data,
        readOriginal: @escaping @Sendable () throws -> Data,
        writeCached: @escaping @Sendable (Data) throws -> Void
    ) async throws -> Data {
        if let task = inFlight[id] {
            return try await task.value
        }

        do {
            return try readCached()
        } catch {
            // Cache misses and cache read failures are both self-healed by regenerating
            // from the canonical original file.
        }

        let task = Task { [shortSidePixels, generate] in
            try await self.runWithPermit {
                let original = try readOriginal()
                let thumbnail = try await generate(original, shortSidePixels)
                try writeCached(thumbnail)
                return thumbnail
            }
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }

    private func runWithPermit(_ operation: @Sendable () async throws -> Data) async throws -> Data {
        await acquirePermit()
        do {
            let data = try await operation()
            releasePermit()
            return data
        } catch {
            releasePermit()
            throw error
        }
    }

    private func acquirePermit() async {
        if activeCount < concurrencyLimit {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releasePermit() {
        if waiters.isEmpty {
            activeCount -= 1
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
