#if canImport(UIKit)
import CoreLocation
import Dependencies
import MapKit
import UIKit

public struct ImageryPair: @unchecked Sendable {
  public var lookAround: UIImage?
  public var angledMap: UIImage?
  public var lookAroundError: String?
  public var angledMapError: String?

  public init(
    lookAround: UIImage? = nil,
    angledMap: UIImage? = nil,
    lookAroundError: String? = nil,
    angledMapError: String? = nil
  ) {
    self.lookAround = lookAround
    self.angledMap = angledMap
    self.lookAroundError = lookAroundError
    self.angledMapError = angledMapError
  }
}

public struct UrbaneImageryClient: Sendable {
  public var preview: @MainActor @Sendable (_ address: String) async -> ImageryPair

  public init(preview: @escaping @MainActor @Sendable (_ address: String) async -> ImageryPair) {
    self.preview = preview
  }

  public static let live = Self { address in
    let mapItem: MKMapItem
    do {
      var request = MKLocalSearch.Request()
      request.naturalLanguageQuery = address
      let response = try await MKLocalSearch(request: request).start()
      guard let first = response.mapItems.first else {
        return ImageryPair(lookAroundError: "No MapKit match", angledMapError: "No MapKit match")
      }
      mapItem = first
    } catch {
      return ImageryPair(
        lookAroundError: "Place search failed: \(error.localizedDescription)",
        angledMapError: "Place search failed: \(error.localizedDescription)"
      )
    }

    let angledMapResult = await Self.angledSnapshot(for: mapItem)
    let lookAroundResult = await Self.lookAroundSnapshot(for: mapItem)
    return ImageryPair(
      lookAround: lookAroundResult.image,
      angledMap: angledMapResult.image,
      lookAroundError: lookAroundResult.error,
      angledMapError: angledMapResult.error
    )
  }

  private static func lookAroundSnapshot(for mapItem: MKMapItem) async -> (image: UIImage?, error: String?) {
    do {
      guard let scene = try await MKLookAroundSceneRequest(mapItem: mapItem).scene else {
        return (nil, "No Look Around coverage")
      }
      let options = MKLookAroundSnapshotter.Options()
      options.size = snapshotSize
      let snapshot = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot
      return (snapshot.image, nil)
    } catch {
      return (nil, error.localizedDescription)
    }
  }

  private static func angledSnapshot(for mapItem: MKMapItem) async -> (image: UIImage?, error: String?) {
    let options = MKMapSnapshotter.Options()
    options.size = snapshotSize
    options.mapType = .standard
    options.showsBuildings = true
    options.camera = MKMapCamera(
      lookingAtCenter: mapItem.location.coordinate,
      fromDistance: postcardCamera.distanceMeters,
      pitch: postcardCamera.pitchDegrees,
      heading: postcardCamera.headingOffsetDegrees
    )
    do {
      let snapshot = try await MKMapSnapshotter(options: options).start()
      return (snapshot.image, nil)
    } catch {
      return (nil, error.localizedDescription)
    }
  }

  private static let snapshotSize = CGSize(width: 600, height: 400)

  /// Shared postcard framing; the S1 device proof decides whether it is useful.
  private static let postcardCamera = PostcardCamera(
    pitchDegrees: 55,
    distanceMeters: 350,
    headingOffsetDegrees: 30
  )
}

private struct PostcardCamera {
  let pitchDegrees: CGFloat
  let distanceMeters: CLLocationDistance
  let headingOffsetDegrees: CLLocationDirection
}

private enum UrbaneImageryClientKey: DependencyKey {
  static let liveValue = UrbaneImageryClient.live
  static let testValue = UrbaneImageryClient { _ in ImageryPair() }
}

extension DependencyValues {
  public var urbaneImageryClient: UrbaneImageryClient {
    get { self[UrbaneImageryClientKey.self] }
    set { self[UrbaneImageryClientKey.self] = newValue }
  }
}
#else
import Dependencies

public struct ImageryPair: Sendable {
  public var lookAroundError = "Imagery proof is available in the iPad app."
  public var angledMapError = "Imagery proof is available in the iPad app."

  public init() {}
}

public struct UrbaneImageryClient: Sendable {
  public var preview: @MainActor @Sendable (_ address: String) async -> ImageryPair

  public init(preview: @escaping @MainActor @Sendable (_ address: String) async -> ImageryPair) {
    self.preview = preview
  }

  public static let live = Self { _ in ImageryPair() }
}
#endif
