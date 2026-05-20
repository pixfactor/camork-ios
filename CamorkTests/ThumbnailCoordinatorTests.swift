import Testing
import Foundation
import GRDB
@testable import Camork

@Suite("ThumbnailCoordinator")
struct ThumbnailCoordinatorTests {
    @Test("MediaStorage.loadThumbnailData: cache hit returns thumb without generator or original read")
    func mediaStorageCacheHitSkipsGenerator() async throws {
        let fakeFs = FakeFileOps()
        let id = UUID()
        let thumb = Data([0xAA, 0xBB])
        try fakeFs.writeThumb(fileName: "\(id.uuidString).jpg", data: thumb)
        let generatorCalls = AsyncCallCounter()
        let storage = try makeStorage(
            fs: fakeFs,
            thumbnailCoordinator: ThumbnailCoordinator(generate: { _, _ in
                await generatorCalls.increment()
                return Data([0x00])
            })
        )

        let data = try await storage.loadThumbnailData(for: makePhoto(id: id))

        #expect(data == thumb)
        #expect(await generatorCalls.value == 0)
    }

    @Test("MediaStorage.loadThumbnailData: cache miss reads original, writes thumb, returns generated data")
    func mediaStorageCacheMissWritesThumb() async throws {
        let fakeFs = FakeFileOps()
        let id = UUID()
        let originalName = "\(id.uuidString).heic"
        let generated = Data([0x10, 0x20, 0x30])
        try fakeFs.writeStaging(fileName: originalName, data: Data([0x01, 0x02]))
        try fakeFs.moveStagingToFinal(fileName: originalName)
        let storage = try makeStorage(
            fs: fakeFs,
            thumbnailCoordinator: ThumbnailCoordinator(generate: { _, _ in generated })
        )

        let data = try await storage.loadThumbnailData(for: makePhoto(id: id))

        #expect(data == generated)
        #expect(try fakeFs.readThumb(fileName: "\(id.uuidString).jpg") == generated)
    }

    @Test("ThumbnailCoordinator: 10 same-photo misses coalesce into one generator call")
    func samePhotoMissesCoalesce() async throws {
        let id = UUID()
        let store = ThumbnailTestStore(original: Data([0x01]))
        let startGate = AsyncStartGate(count: 10)
        let generatorGate = AsyncManualGate()
        let generatorCalls = AsyncCallCounter()
        let launchedCalls = AsyncCallCounter()
        let readAttempts = SyncIntCounter()
        let coordinator = ThumbnailCoordinator(generate: { _, _ in
            await generatorCalls.increment()
            await generatorGate.wait()
            return Data([0x99])
        })

        let tasks = (0..<10).map { _ in
            Task {
                await startGate.wait()
                await launchedCalls.increment()
                return try await coordinator.loadThumbnailData(
                    id: id,
                    readCached: {
                        readAttempts.increment()
                        return try store.readCached()
                    },
                    generateAndCache: {
                        let original = try store.readOriginal()
                        let thumbnail = try await coordinator.generate(
                            original,
                            coordinator.shortSidePixels
                        )
                        try store.writeCached(thumbnail)
                        return thumbnail
                    }
                )
            }
        }

        await launchedCalls.waitUntilValue(10)
        await generatorCalls.waitUntilValue(1)
        #expect(readAttempts.value == 1)
        await generatorGate.open()

        for task in tasks {
            #expect(try await task.value == Data([0x99]))
        }
        #expect(await generatorCalls.value == 1)
        #expect(readAttempts.value == 1)
    }

    @Test("ThumbnailCoordinator: distinct misses are bounded to concurrency limit 4")
    func distinctMissesRespectConcurrencyLimit() async throws {
        let probe = ConcurrencyProbe()
        let coordinator = ThumbnailCoordinator(concurrencyLimit: 4, generate: { data, _ in
            await probe.enter()
            await probe.waitForRelease()
            await probe.leave()
            return Data([data.first ?? 0x00, 0xFF])
        })
        let stores = (0..<5).map { ThumbnailTestStore(original: Data([UInt8($0)])) }
        let ids = (0..<5).map { _ in UUID() }
        let startGate = AsyncStartGate(count: 5)

        let tasks = zip(ids, stores).map { id, store in
            Task {
                await startGate.wait()
                return try await coordinator.loadThumbnailData(
                    id: id,
                    readCached: {
                        try store.readCached()
                    },
                    generateAndCache: {
                        let original = try store.readOriginal()
                        let thumbnail = try await coordinator.generate(
                            original,
                            coordinator.shortSidePixels
                        )
                        try store.writeCached(thumbnail)
                        return thumbnail
                    }
                )
            }
        }

        await probe.waitUntilStarted(4)
        #expect(await probe.startedCount == 4)
        #expect(await probe.maxActiveCount == 4)

        await probe.release(1)
        await probe.waitUntilStarted(5)
        #expect(await probe.startedCount == 5)
        #expect(await probe.maxActiveCount == 4)

        await probe.release(4)
        for task in tasks {
            _ = try await task.value
        }
        #expect(await probe.maxActiveCount == 4)
    }

    @Test("MediaStorage.loadThumbnailData: invalid canonical fileName throws before thumb cache read")
    func mediaStorageInvalidFileNameRejectsBeforeCache() async throws {
        let fakeFs = FakeFileOps()
        let id = UUID()
        try fakeFs.writeThumb(fileName: "\(id.uuidString).jpg", data: Data([0xAA]))
        let generatorCalls = AsyncCallCounter()
        let storage = try makeStorage(
            fs: fakeFs,
            thumbnailCoordinator: ThumbnailCoordinator(generate: { _, _ in
                await generatorCalls.increment()
                return Data([0x00])
            })
        )
        let corrupted = makePhoto(id: id, fileName: "../../\(id.uuidString).heic")

        await #expect(throws: MediaStorage.Error.invalidFileName) {
            _ = try await storage.loadThumbnailData(for: corrupted)
        }
        #expect(await generatorCalls.value == 0)
    }
}

// MARK: - Helpers

private enum ThumbnailTestError: Swift.Error {
    case cacheMiss
}

private func makeStorage(
    fs: any FileOps,
    thumbnailCoordinator: ThumbnailCoordinator
) throws -> MediaStorage {
    let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
    try Migrations.makeMigrator().migrate(db)
    return MediaStorage(db: db, fs: fs, thumbnailCoordinator: thumbnailCoordinator)
}

private func makePhoto(id: UUID, fileName: String? = nil) -> Photo {
    Photo(
        id: id,
        sessionId: UUID(),
        fileName: fileName ?? "\(id.uuidString).heic",
        kind: .photo,
        capturedAt: Date(timeIntervalSince1970: 0)
    )
}

private final class ThumbnailTestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: Data?
    private let original: Data

    init(original: Data, cached: Data? = nil) {
        self.original = original
        self.cached = cached
    }

    func readCached() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let cached else { throw ThumbnailTestError.cacheMiss }
        return cached
    }

    func readOriginal() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return original
    }

    func writeCached(_ data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        cached = data
    }
}

private final class SyncIntCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        storage += 1
    }
}

private actor AsyncCallCounter {
    private var storage = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var value: Int { storage }

    func increment() {
        storage += 1
        resumeSatisfiedWaiters()
    }

    func waitUntilValue(_ target: Int) async {
        if storage >= target { return }
        await withCheckedContinuation { continuation in
            waiters.append((target, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if storage >= waiter.target {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

private actor AsyncStartGate {
    private let target: Int
    private var arrived = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) {
        self.target = count
    }

    func wait() async {
        arrived += 1
        if arrived >= target {
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor AsyncManualGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ConcurrencyProbe {
    private var active = 0
    private var maxActive = 0
    private var started = 0
    private var startWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseCredits = 0
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    var startedCount: Int { started }
    var maxActiveCount: Int { maxActive }

    func enter() {
        active += 1
        started += 1
        maxActive = max(maxActive, active)
        resumeSatisfiedStartWaiters()
    }

    func leave() {
        active -= 1
    }

    func waitUntilStarted(_ target: Int) async {
        if started >= target { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((target, continuation))
        }
    }

    func waitForRelease() async {
        if releaseCredits > 0 {
            releaseCredits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release(_ count: Int) {
        for _ in 0..<count {
            if releaseWaiters.isEmpty {
                releaseCredits += 1
            } else {
                releaseWaiters.removeFirst().resume()
            }
        }
    }

    private func resumeSatisfiedStartWaiters() {
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in startWaiters {
            if started >= waiter.target {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        startWaiters = remaining
    }
}
