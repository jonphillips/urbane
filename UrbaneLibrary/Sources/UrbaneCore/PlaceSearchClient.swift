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

/// The one place-search boundary shared by manual entry and chat import.
public struct PlaceSearchClient: Sendable {
  public var search: @Sendable (String) async throws -> [PlaceMatch]

  public init(search: @escaping @Sendable (String) async throws -> [PlaceMatch]) {
    self.search = search
  }
}

public enum PlaceSearchRowResolution: Equatable, Sendable {
  case matches([PlaceMatch])
  case unresolved(String)
}

/// Turns a place lookup failure into a row-level review result without losing other rows.
public enum PlaceSearchRows {
  public static func resolve(query: String, using client: PlaceSearchClient) async throws -> PlaceSearchRowResolution {
    do {
      return .matches(try await client.search(query))
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

extension PlaceSearchClient: DependencyKey {
  public static let liveValue = PlaceSearchClient { query in
    let response: MKLocalSearch.Response
    var attempt = 0
    while true {
      var request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.94),
        span: MKCoordinateSpan(latitudeDelta: 0.48, longitudeDelta: 0.72)
      )
      do {
        response = try await MKLocalSearch(request: request).start()
        break
      } catch {
        let nsError = error as NSError
        switch PlaceSearchFailureDisposition.classify(domain: nsError.domain, code: nsError.code) {
        case .noMatch: return []
        case .throttled where attempt < 2:
          attempt += 1
          try await Task.sleep(for: .milliseconds(250 * attempt))
        case .throttled, .other: throw error
        }
      }
    }
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

  public static let testValue = PlaceSearchClient { _ in [] }
}

public extension DependencyValues {
  var placeSearch: PlaceSearchClient {
    get { self[PlaceSearchClient.self] }
    set { self[PlaceSearchClient.self] = newValue }
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
