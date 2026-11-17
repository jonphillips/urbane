import CoreLocation
import CryptoKit
import Foundation
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
  func postcard(latitude: Double, longitude: Double, mapItemIdentifier: String?) async -> UIImage? {
    let recipe = "hybrid3d|\(latitude)|\(longitude)|\(mapItemIdentifier ?? "coordinate")|55|350|30|600x400"
    if let cached = Self.cachedImage(for: recipe) { return cached }
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let options = MKMapSnapshotter.Options()
    options.size = Self.snapshotSize
    options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
    options.camera = MKMapCamera(lookingAtCenter: coordinate, fromDistance: 350, pitch: 55, heading: 30)
    do {
      let image = try await MKMapSnapshotter(options: options).start().image
      Self.cache(image, for: recipe)
      return image
    } catch {
      return nil
    }
  }

  func lookAroundScene(latitude: Double, longitude: Double, mapItemIdentifier: String?) async -> MKLookAroundScene? {
    if let mapItemIdentifier,
       let identifier = MKMapItem.Identifier(rawValue: mapItemIdentifier) {
      do {
        let mapItem = try await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
        if let scene = try await MKLookAroundSceneRequest(mapItem: mapItem).scene { return scene }
      } catch {}
    }
    return try? await MKLookAroundSceneRequest(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    ).scene
  }

  func lookAroundSnapshot(latitude: Double, longitude: Double, mapItemIdentifier: String?) async -> UIImage? {
    let recipe = "lookaround|\(latitude)|\(longitude)|\(mapItemIdentifier ?? "coordinate")|600x400"
    if let cached = Self.cachedImage(for: recipe) { return cached }
    guard let scene = await lookAroundScene(latitude: latitude, longitude: longitude, mapItemIdentifier: mapItemIdentifier) else { return nil }
    let options = MKLookAroundSnapshotter.Options()
    options.size = Self.snapshotSize
    do {
      let image = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot.image
      Self.cache(image, for: recipe)
      return image
    } catch {
      return nil
    }
  }

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

  private static func cachedImage(for recipe: String) -> UIImage? {
    guard let url = cacheURL(for: recipe), let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }

  private static func cache(_ image: UIImage, for recipe: String) {
    guard let data = image.jpegData(compressionQuality: 0.84), let url = cacheURL(for: recipe) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  private static func cacheURL(for recipe: String) -> URL? {
    guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    let name = SHA256.hash(data: Data(recipe.utf8)).map { String(format: "%02x", $0) }.joined()
    return cache.appendingPathComponent("UrbanePostcards", isDirectory: true).appendingPathComponent("\(name).jpg")
  }
}

private struct PostcardCamera {
  let pitchDegrees: CGFloat
  let distanceMeters: CLLocationDistance
  let headingDegrees: CLLocationDirection
}
