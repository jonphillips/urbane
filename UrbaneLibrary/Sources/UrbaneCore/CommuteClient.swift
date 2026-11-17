import Dependencies
import MapKit
import UrbaneSchema

public struct CommuteClient: Sendable {
  public var transitSeconds: @Sendable (_ origin: GeoCoordinate, _ destination: GeoCoordinate) async throws -> Int

  public init(
    transitSeconds: @escaping @Sendable (_ origin: GeoCoordinate, _ destination: GeoCoordinate) async throws -> Int
  ) {
    self.transitSeconds = transitSeconds
  }
}

extension CommuteClient: DependencyKey {
  public static let liveValue = CommuteClient { origin, destination in
    @Dependency(\.mapKitRequestPacer) var pacer
    return try await pacer.request {
      let request = MKDirections.Request()
      request.source = MKMapItem(location: CLLocation(
        latitude: origin.latitude, longitude: origin.longitude
      ), address: nil)
      request.destination = MKMapItem(location: CLLocation(
        latitude: destination.latitude, longitude: destination.longitude
      ), address: nil)
      request.transportType = .transit
      let response = try await MKDirections(request: request).calculateETA()
      return Int(response.expectedTravelTime.rounded())
    }
  }

  public static let testValue = CommuteClient { _, _ in 0 }
}

extension DependencyValues {
  public var commuteClient: CommuteClient {
    get { self[CommuteClient.self] }
    set { self[CommuteClient.self] = newValue }
  }
}
