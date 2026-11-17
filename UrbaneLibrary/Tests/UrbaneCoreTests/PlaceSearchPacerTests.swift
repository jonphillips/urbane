import Foundation
import Testing
import UrbaneCore

@Suite struct PlaceSearchPacerTests {
  @Test func pacesOneHundredSearchesWithinRollingWindow() async throws {
    let clock = PacerTestClock()
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let starts = SearchStartLog()
    for index in 0..<100 {
      _ = try await pacer.search(query: "\(index)", using: { _ in
        await starts.append(await clock.now())
        return []
      })
    }
    let times = await starts.values
    #expect(times.count == 100)
    #expect(times.allSatisfy { start in
      times.filter { $0 >= start && $0 - start < .seconds(60) }.count <= 45
    })
    #expect(await clock.now() >= .seconds(60))
  }

  @Test func placeSearchesAndTransitRequestsShareOneBudget() async throws {
    let clock = PacerTestClock()
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let starts = SearchStartLog()
    for index in 0..<25 {
      _ = try await pacer.search(query: "place \(index)", using: { _ in
        await starts.append(await clock.now())
        return []
      })
    }
    for _ in 0..<25 {
      _ = try await pacer.request {
        await starts.append(await clock.now())
        return 1
      }
    }
    let times = await starts.values
    #expect(times.count == 50)
    #expect(times.allSatisfy { start in
      times.filter { $0 >= start && $0 - start < .seconds(60) }.count <= 45
    })
    #expect(await clock.now() >= .seconds(60))
  }

  @Test func concurrentCallersStillRunSearchesSequentially() async throws {
    let clock = PacerTestClock()
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let activity = SearchActivity()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<8 {
        group.addTask {
          _ = try await pacer.search(query: "\(index)", using: { _ in
            await activity.started()
            try await clock.sleep(for: .seconds(2))
            await activity.finished()
            return []
          })
        }
      }
      try await group.waitForAll()
    }
    #expect(await activity.maximumActive == 1)
  }

  @Test func throttledSearchWaitsSixtySecondsThenSucceeds() async throws {
    let clock = PacerTestClock()
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let starts = SearchStartLog()
    let attempts = AttemptCounter()
    let matches = try await pacer.search(query: "Brooklyn", using: { _ in
      let attempt = await attempts.increment()
      await starts.append(await clock.now())
      if attempt == 1 { throw Self.throttledError }
      return []
    })
    #expect(matches.isEmpty)
    #expect(await starts.values == [.zero, .seconds(60)])
    #expect(await clock.now() == .seconds(60))
  }

  @Test func fourthThrottleReturnsUnresolvedAfterThreeWaits() async throws {
    let clock = PacerTestClock()
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let attempts = AttemptCounter()
    let client = PlaceSearchClient(searchWithProgress: { query, onWaiting in
      try await pacer.search(query: query, using: { _ in
        _ = await attempts.increment()
        throw Self.throttledError
      }, onWaiting: onWaiting)
    })
    let result = try await PlaceSearchRows.resolve(query: "Park Slope", using: client)
    guard case .unresolved(let message) = result else {
      Issue.record("Expected the fourth throttle to remain unresolved")
      return
    }
    #expect(message.contains("loadingThrottled"))
    #expect(await attempts.value == 4)
    #expect(await clock.now() == .seconds(180))
  }

  @Test func placemarkNotFoundReturnsNoMatchesWithoutWaiting() async throws {
    let clock = PacerTestClock()
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let attempts = AttemptCounter()
    let matches = try await pacer.search(query: "Missing place", using: { _ in
      _ = await attempts.increment()
      throw NSError(domain: "MKErrorDomain", code: 4)
    })
    #expect(matches.isEmpty)
    #expect(await attempts.value == 1)
    #expect(await clock.now() == .zero)
  }

  @Test func cancellingDuringThrottleWaitEndsPromptly() async throws {
    let clock = PacerTestClock(automaticallyAdvances: false)
    let pacer = PlaceSearchPacer(clock: await clock.client)
    let task = Task {
      try await pacer.search(query: "Williamsburg", using: { _ in
        throw Self.throttledError
      })
    }
    await clock.waitUntilSleeping()
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("Expected cancellation to end the wait")
    } catch is CancellationError {
      #expect(await clock.pendingSleepCount == 0)
    }
  }

  private static var throttledError: NSError {
    NSError(domain: "MKErrorDomain", code: 3, userInfo: [NSLocalizedDescriptionKey: "Apple Maps loadingThrottled"])
  }
}

private actor PacerTestClock {
  private var instant: Duration = .zero
  private let automaticallyAdvances: Bool
  private var sleepers: [UUID: CheckedContinuation<Void, any Error>] = [:]
  private var sleepAnnouncement: CheckedContinuation<Void, Never>?

  init(automaticallyAdvances: Bool = true) {
    self.automaticallyAdvances = automaticallyAdvances
  }

  var client: PlaceSearchClock {
    PlaceSearchClock(
      now: { await self.now() },
      sleep: { try await self.sleep(for: $0) }
    )
  }

  var pendingSleepCount: Int { sleepers.count }

  func now() -> Duration { instant }

  func sleep(for duration: Duration) async throws {
    guard !Task.isCancelled else { throw CancellationError() }
    if automaticallyAdvances {
      instant += duration
      return
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        sleepers[id] = continuation
        sleepAnnouncement?.resume()
        sleepAnnouncement = nil
      }
    } onCancel: {
      Task { await self.cancelSleep(id) }
    }
  }

  func waitUntilSleeping() async {
    if !sleepers.isEmpty { return }
    await withCheckedContinuation { sleepAnnouncement = $0 }
  }

  private func cancelSleep(_ id: UUID) {
    sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}

private actor SearchStartLog {
  private(set) var values: [Duration] = []
  func append(_ value: Duration) { values.append(value) }
}

private actor AttemptCounter {
  private(set) var value = 0
  func increment() -> Int { value += 1; return value }
}

private actor SearchActivity {
  private var active = 0
  private(set) var maximumActive = 0

  func started() {
    active += 1
    maximumActive = max(maximumActive, active)
  }

  func finished() { active -= 1 }
}
