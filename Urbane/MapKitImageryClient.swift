import CoreLocation
import MapKit
import UIKit

struct ImageryPair {
  var matchedName: String?
  var matchedLatitude: CLLocationDegrees?
  var matchedLongitude: CLLocationDegrees?
  var matchKind: String?
  var lookAround: UIImage?
  var standard3D: UIImage?
  var hybrid3D: UIImage?
  var searchError: String?
  var lookAroundError: String?
  var standard3DError: String?
  var hybrid3DError: String?
}

struct UrbaneImageryClient {
  func preview(placeName: String, address: String) async -> ImageryPair {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = "\(placeName), \(address)"
    do {
      let response = try await MKLocalSearch(request: request).start()
      guard let mapItem = response.mapItems.first else {
        return ImageryPair(searchError: "MapKit found no matching place.")
      }
      return await Self.snapshots(for: mapItem)
    } catch {
      return ImageryPair(searchError: "Place search failed: \(error.localizedDescription)")
    }
  }

  private static func snapshots(for mapItem: MKMapItem) async -> ImageryPair {
    let coordinate = mapItem.location.coordinate
    var result = ImageryPair(
      matchedName: mapItem.name ?? "Unnamed MapKit result",
      matchedLatitude: coordinate.latitude,
      matchedLongitude: coordinate.longitude,
      matchKind: mapItem.pointOfInterestCategory == nil ? "Bare address" : "Point of interest"
    )

    do {
      let snapshot = try await mapSnapshot(
        for: mapItem,
        configuration: MKStandardMapConfiguration(elevationStyle: .realistic)
      )
      result.standard3D = snapshot
    } catch {
      result.standard3DError = error.localizedDescription
    }

    do {
      let snapshot = try await mapSnapshot(
        for: mapItem,
        configuration: MKHybridMapConfiguration(elevationStyle: .realistic)
      )
      result.hybrid3D = snapshot
    } catch {
      result.hybrid3DError = error.localizedDescription
    }

    do {
      guard let scene = try await MKLookAroundSceneRequest(mapItem: mapItem).scene else {
        result.lookAroundError = "No Look Around coverage for this map item."
        return result
      }
      let options = MKLookAroundSnapshotter.Options()
      options.size = snapshotSize
      result.lookAround = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
    } catch {
      result.lookAroundError = error.localizedDescription
    }
    return result
  }

  private static func mapSnapshot(
    for mapItem: MKMapItem,
    configuration: MKMapConfiguration
  ) async throws -> UIImage {
    let options = MKMapSnapshotter.Options()
    options.size = snapshotSize
    options.preferredConfiguration = configuration
    options.camera = MKMapCamera(
      lookingAtCenter: mapItem.location.coordinate,
      fromDistance: postcardCamera.distanceMeters,
      pitch: postcardCamera.pitchDegrees,
      heading: postcardCamera.headingDegrees
    )
    return try await MKMapSnapshotter(options: options).start().image
  }

  private static let snapshotSize = CGSize(width: 600, height: 400)
  private static let postcardCamera = PostcardCamera(
    pitchDegrees: 55,
    distanceMeters: 350,
    headingDegrees: 30
  )
}

private struct PostcardCamera {
  let pitchDegrees: CGFloat
  let distanceMeters: CLLocationDistance
  let headingDegrees: CLLocationDirection
}
