import CoreLocation
import Dependencies
import MapKit
import UrbaneSchema

struct TransitDirectionsClient: Sendable {
  var open: @MainActor @Sendable (Building, CommuteDestination) async -> Void
}

extension TransitDirectionsClient: DependencyKey {
  static let liveValue = TransitDirectionsClient { building, destination in
    let origin: MKMapItem
    if let rawIdentifier = building.mapItemIdentifier,
       let identifier = MKMapItem.Identifier(rawValue: rawIdentifier) {
      do {
        origin = try await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
      } catch {
        origin = Self.buildingMapItem(for: building)
      }
    } else {
      origin = Self.buildingMapItem(for: building)
    }

    let destinationMapItem = MKMapItem(location: CLLocation(
      latitude: destination.coordinate.latitude,
      longitude: destination.coordinate.longitude
    ), address: nil)
    destinationMapItem.name = destination.displayName
    MKMapItem.openMaps(
      with: [origin, destinationMapItem],
      launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit]
    )
  }

  private static func buildingMapItem(for building: Building) -> MKMapItem {
    let item = MKMapItem(location: CLLocation(latitude: building.latitude, longitude: building.longitude), address: nil)
    item.name = building.name
    return item
  }
}

extension DependencyValues {
  var transitDirectionsClient: TransitDirectionsClient {
    get { self[TransitDirectionsClient.self] }
    set { self[TransitDirectionsClient.self] = newValue }
  }
}
