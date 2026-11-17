import Dependencies
import Foundation
import MapKit

public struct PlaceMatch: Equatable, Sendable, Identifiable {
  public var id: String { mapItemIdentifier ?? "\(latitude),\(longitude),\(name)" }
  public var name: String
  public var address: String
  public var latitude: Double
  public var longitude: Double
  public var mapItemIdentifier: String?

  public init(name: String, address: String, latitude: Double, longitude: Double, mapItemIdentifier: String?) {
    self.name = name
    self.address = address
    self.latitude = latitude
    self.longitude = longitude
    self.mapItemIdentifier = mapItemIdentifier
  }
}

/// A monotonic clock boundary used by the shared place-search pacer.
public struct PlaceSearchClock: Sendable {
  public var now: @Sendable () async -> Duration
  public var sleep: @Sendable (Duration) async throws -> Void

  public init(
    now: @escaping @Sendable () async -> Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) {
    self.now = now
    self.sleep = sleep
  }

  public static func live(_ clock: ContinuousClock = ContinuousClock()) -> Self {
    let origin = clock.now
    return Self(
      now: { clock.now - origin },
      sleep: { try await clock.sleep(for: $0) }
    )
  }
}

/// The one place-search boundary shared by manual entry and chat import.
public struct PlaceSearchClient: Sendable {
  public var search: @Sendable (String, @escaping @Sendable (Duration?) async -> Void) async throws -> [PlaceMatch]

  public init(search: @escaping @Sendable (String) async throws -> [PlaceMatch]) {
    self.search = { query, _ in try await search(query) }
  }

  public init(
    searchWithProgress: @escaping @Sendable (String, @escaping @Sendable (Duration?) async -> Void) async throws -> [PlaceMatch]
  ) {
    self.search = searchWithProgress
  }
}

public enum PlaceSearchRowResolution: Equatable, Sendable {
  case matches([PlaceMatch])
  case unresolved(String)
}

/// Turns a place lookup failure into a row-level review result without losing other rows.
public enum PlaceSearchRows {
  public static func resolve(
    query: String,
    using client: PlaceSearchClient,
    onWaiting: @escaping @Sendable (Duration?) async -> Void = { _ in }
  ) async throws -> PlaceSearchRowResolution {
    do {
      return .matches(try await client.search(query, onWaiting))
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return .unresolved(error.localizedDescription)
    }
  }
}

public enum PlaceSearchFailureDisposition: Equatable, Sendable {
  case noMatch
  case throttled
  case other

  public static func classify(domain: String, code: Int) -> Self {
    guard domain == "MKErrorDomain" else { return .other }
    switch code {
    case 4: return .noMatch // MKError.Code.placemarkNotFound
    case 3: return .throttled // MKError.Code.loadingThrottled
    default: return .other
    }
  }
}

/// Serializes MapKit requests and enforces Apple's shared request budget.
public actor PlaceSearchPacer {
  // Apple's limit is 50 requests per 60 seconds. A 45 request budget reserves five
  // requests for searches outside this client (50 - 45) within that same window.
  private static let maximumSearches = 45
  private static let window: Duration = .seconds(60)
  // 60 seconds / 45 searches = 1.333… seconds; round up to milliseconds to
  // preserve headroom at the boundary while distributing a full seed over time.
  private static let minimumInterval: Duration = .milliseconds(1_334)
  private static let throttleWait: Duration = .seconds(60)
  private static let maximumThrottleWaits = 3

  private let clock: PlaceSearchClock
  private var searchTimes: [Duration] = []
  private var isRunningSearch = false
  private var waiters: [(UUID, CheckedContinuation<Void, any Error>)] = []

  public init(clock: PlaceSearchClock) {
    self.clock = clock
  }

  public func search(
    query: String,
    using operation: @escaping @Sendable (String) async throws -> [PlaceMatch],
    onWaiting: @escaping @Sendable (Duration?) async -> Void = { _ in }
  ) async throws -> [PlaceMatch] {
    do {
      return try await request(onWaiting: onWaiting) { try await operation(query) }
    } catch {
      if Self.disposition(for: error) == .noMatch { return [] }
      throw error
    }
  }

  public func request<Value: Sendable>(
    onWaiting: @escaping @Sendable (Duration?) async -> Void = { _ in },
    using operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await acquire()
    defer { release() }

    var throttleWaits = 0
    while true {
      try await waitForSlot(onWaiting: onWaiting)
      do {
        return try await operation()
      } catch {
        switch Self.disposition(for: error) {
        case .noMatch:
          throw error
        case .throttled where throttleWaits < Self.maximumThrottleWaits:
          throttleWaits += 1
          try await wait(Self.throttleWait, onWaiting: onWaiting)
        case .throttled, .other:
          throw error
        }
      }
    }
  }

  private func waitForSlot(onWaiting: @escaping @Sendable (Duration?) async -> Void) async throws {
    while true {
      try Task.checkCancellation()
      let now = await clock.now()
      searchTimes.removeAll { now - $0 >= Self.window }
      let intervalWait = searchTimes.last.map { max(.zero, $0 + Self.minimumInterval - now) } ?? .zero
      let windowWait: Duration
      if searchTimes.count >= Self.maximumSearches, let oldest = searchTimes.first {
        windowWait = max(.zero, oldest + Self.window - now)
      } else {
        windowWait = .zero
      }
      let waitDuration = max(intervalWait, windowWait)
      guard waitDuration <= .zero else {
        try await wait(waitDuration, onWaiting: onWaiting)
        continue
      }
      guard searchTimes.count < Self.maximumSearches else {
        continue
      }
      searchTimes.append(now)
      await onWaiting(nil)
      return
    }
  }

  private func wait(
    _ duration: Duration,
    onWaiting: @escaping @Sendable (Duration?) async -> Void
  ) async throws {
    try Task.checkCancellation()
    await onWaiting(duration)
    do {
      try await clock.sleep(duration)
      try Task.checkCancellation()
      await onWaiting(nil)
    } catch is CancellationError {
      await onWaiting(nil)
      throw CancellationError()
    }
  }

  private func acquire() async throws {
    guard isRunningSearch else {
      isRunningSearch = true
      return
    }

    let id = UUID()
    _ = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters.append((id, continuation))
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
    guard !Task.isCancelled else {
      release()
      throw CancellationError()
    }
  }

  private func release() {
    if waiters.isEmpty {
      isRunningSearch = false
    } else {
      waiters.removeFirst().1.resume()
    }
  }

  private func cancelWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
    waiters.remove(at: index).1.resume(throwing: CancellationError())
  }

  private static func disposition(for error: any Error) -> PlaceSearchFailureDisposition {
    let nsError = error as NSError
    return PlaceSearchFailureDisposition.classify(domain: nsError.domain, code: nsError.code)
  }
}

extension PlaceSearchClient: DependencyKey {
  public static let liveValue: Self = {
    let search: @Sendable (String) async throws -> [PlaceMatch] = { query in
      var request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.94),
        span: MKCoordinateSpan(latitudeDelta: 0.48, longitudeDelta: 0.72)
      )
      let response = try await MKLocalSearch(request: request).start()
      return response.mapItems.compactMap { item in
        let coordinate = item.location.coordinate
        guard NYC.contains(coordinate.latitude, coordinate.longitude) else { return nil }
        let address = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) ?? ""
        return PlaceMatch(
          name: item.name ?? address,
          address: address,
          latitude: coordinate.latitude,
          longitude: coordinate.longitude,
          mapItemIdentifier: item.identifier?.rawValue
        )
      }
    }
    return PlaceSearchClient(searchWithProgress: { query, onWaiting in
      @Dependency(\.mapKitRequestPacer) var pacer
      return try await pacer.search(query: query, using: search, onWaiting: onWaiting)
    })
  }()

  public static let testValue = PlaceSearchClient { _ in [] }
}

private enum MapKitRequestPacerKey: DependencyKey {
  static let liveValue = PlaceSearchPacer(clock: .live())
  static let testValue = PlaceSearchPacer(clock: .live())
}

public extension DependencyValues {
  var placeSearch: PlaceSearchClient {
    get { self[PlaceSearchClient.self] }
    set { self[PlaceSearchClient.self] = newValue }
  }

  var mapKitRequestPacer: PlaceSearchPacer {
    get { self[MapKitRequestPacerKey.self] }
    set { self[MapKitRequestPacerKey.self] = newValue }
  }
}

private enum NYC {
  static func contains(_ latitude: Double, _ longitude: Double) -> Bool {
    let inManhattan = (40.70...40.88).contains(latitude) && (-74.02 ... -73.90).contains(longitude)
    let inBronx = (40.78...40.92).contains(latitude) && (-73.93 ... -73.75).contains(longitude)
    let inBrooklyn = (40.57...40.74).contains(latitude) && (-74.05 ... -73.83).contains(longitude)
    let inQueens = (40.54...40.80).contains(latitude) && (-73.96 ... -73.70).contains(longitude)
    let inStatenIsland = (40.49...40.65).contains(latitude) && (-74.26 ... -74.05).contains(longitude)
    return inManhattan || inBronx || inBrooklyn || inQueens || inStatenIsland
  }
}
