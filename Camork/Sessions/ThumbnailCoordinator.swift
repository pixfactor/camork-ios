import Foundation

/// Thumbnail cache loading coordinator (Plan C Phase 2.3).
///
/// Responsibilities:
/// - return cache hits without consuming generation concurrency;
/// - coalesce same-photo misses into one in-flight generation task;
/// - cap distinct miss generation work to `concurrencyLimit`.
actor ThumbnailCoordinator {
    /// Pixel target forwarded to the underlying generator on miss. Exposed `nonisolated`
    /// so MediaStorage (or any composer) can hand the value to its `generateAndCache`
    /// closure without round-tripping through the actor.
    nonisolated let shortSidePixels: Int

    /// Pure thumbnail generator (Data, shortSidePixels) -> Data. Exposed `nonisolated`
    /// because the closure is immutable + `@Sendable` and callers must invoke it from
    /// inside the `generateAndCache` closure they pass to `loadThumbnailData`.
    nonisolated let generate: @Sendable (Data, Int) async throws -> Data

    private let concurrencyLimit: Int
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

    /// Algorithm (spec):
    /// 1. If `inFlight[id]` exists, await it (the in-flight task already holds a permit,
    ///    so coalescing callers do not consume an additional slot).
    /// 2. Otherwise try `readCached()` synchronously. Cache hit returns immediately and
    ///    never touches the permit pool — small responses must not stall behind misses.
    /// 3. On cache read failure (miss or corrupt entry), spawn a `Task` that acquires a
    ///    permit, runs `generateAndCache`, releases the permit in `defer`. Store the task
    ///    in `inFlight` *before* awaiting; remove it in `defer` after the await completes,
    ///    success or failure, so the next caller for the same id refreshes from cache.
    func loadThumbnailData(
        id: UUID,
        readCached: @Sendable () throws -> Data,
        generateAndCache: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if let task = inFlight[id] {
            return try await task.value
        }

        do {
            return try readCached()
        } catch {
            // Cache miss or unreadable entry — both self-heal via regeneration.
        }

        let task = Task<Data, Swift.Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.runGuarded(generateAndCache)
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }

    private func runGuarded(
        _ generateAndCache: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        await acquirePermit()
        defer { releasePermit() }
        return try await generateAndCache()
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
