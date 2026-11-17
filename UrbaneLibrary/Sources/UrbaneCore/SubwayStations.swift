import Foundation
import UrbaneSchema

public struct SubwayStation: Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let routes: [String]
  public let latitude: Double
  public let longitude: Double

  public init(id: String, name: String, routes: [String], latitude: Double, longitude: Double) {
    self.id = id
    self.name = name
    self.routes = routes
    self.latitude = latitude
    self.longitude = longitude
  }

  public var coordinate: GeoCoordinate {
    GeoCoordinate(latitude: latitude, longitude: longitude)
  }
}

public struct NearbySubwayStation: Equatable, Sendable {
  public let station: SubwayStation
  public let distanceMeters: Double

  public var approximateWalkMinutes: Int {
    max(1, Int((distanceMeters / SubwayStations.walkingMetersPerMinute).rounded()))
  }
}

public struct SubwayLineStyle: Equatable, Sendable {
  public let fillHex: UInt32
  public let textHex: UInt32
}

public enum SubwayMarkerScale {
  public static let maximumCameraDistance = 10_000.0
  private static let closeCameraDistance = 600.0
  private static let fullSizeCameraDistance = 4_440.0
  private static let closeScale = 1.5
  private static let distantScale = 1.0

  public static func scale(cameraDistance: Double) -> Double {
    if cameraDistance <= closeCameraDistance { return closeScale }
    if cameraDistance >= fullSizeCameraDistance { return distantScale }
    let progress = (cameraDistance - closeCameraDistance) / (fullSizeCameraDistance - closeCameraDistance)
    return closeScale + (distantScale - closeScale) * progress
  }
}

public enum SubwayStations {
  public static let maximumWalkingDistanceMeters = 800.0
  public static let walkingMetersPerMinute = 80.0
  public static let bundled: Result<[SubwayStation], Error> = Result { try load() }

  // This order is the MTA route order used by the app's palette and markers.
  public static let routeOrder = [
    "1", "2", "3", "4", "5", "6", "7", "A", "C", "E", "B", "D", "F", "M", "G",
    "J", "Z", "L", "N", "Q", "R", "S", "W", "SIR",
  ]

  public static let lineStyles: [String: SubwayLineStyle] = [
    "1": .init(fillHex: 0xEE352E, textHex: 0xFFFFFF),
    "2": .init(fillHex: 0xEE352E, textHex: 0xFFFFFF),
    "3": .init(fillHex: 0xEE352E, textHex: 0xFFFFFF),
    "4": .init(fillHex: 0x00933C, textHex: 0xFFFFFF),
    "5": .init(fillHex: 0x00933C, textHex: 0xFFFFFF),
    "6": .init(fillHex: 0x00933C, textHex: 0xFFFFFF),
    "7": .init(fillHex: 0xB933AD, textHex: 0xFFFFFF),
    "A": .init(fillHex: 0x0039A6, textHex: 0xFFFFFF),
    "C": .init(fillHex: 0x0039A6, textHex: 0xFFFFFF),
    "E": .init(fillHex: 0x0039A6, textHex: 0xFFFFFF),
    "B": .init(fillHex: 0xFF6319, textHex: 0xFFFFFF),
    "D": .init(fillHex: 0xFF6319, textHex: 0xFFFFFF),
    "F": .init(fillHex: 0xFF6319, textHex: 0xFFFFFF),
    "M": .init(fillHex: 0xFF6319, textHex: 0xFFFFFF),
    "G": .init(fillHex: 0x6CBE45, textHex: 0x000000),
    "J": .init(fillHex: 0x996633, textHex: 0xFFFFFF),
    "Z": .init(fillHex: 0x996633, textHex: 0xFFFFFF),
    "L": .init(fillHex: 0xA7A9AC, textHex: 0x000000),
    "N": .init(fillHex: 0xFCCC0A, textHex: 0x000000),
    "Q": .init(fillHex: 0xFCCC0A, textHex: 0x000000),
    "R": .init(fillHex: 0xFCCC0A, textHex: 0x000000),
    "W": .init(fillHex: 0xFCCC0A, textHex: 0x000000),
    "S": .init(fillHex: 0x808183, textHex: 0xFFFFFF),
    "SIR": .init(fillHex: 0x808183, textHex: 0xFFFFFF),
  ]

  public static func load() throws -> [SubwayStation] {
    guard let url = Bundle.module.url(forResource: "mta-subway-stations", withExtension: "json") else {
      throw SnapshotError.resourceMissing
    }
    let snapshot = try JSONDecoder().decode(StationSnapshot.self, from: Data(contentsOf: url))
    return try group(snapshot.stations)
  }

  public static func group(_ rows: [StationRow]) throws -> [SubwayStation] {
    var grouped: [String: [StationRow]] = [:]
    var complexOrder: [String] = []
    for row in rows {
      if grouped[row.complexID] == nil {
        grouped[row.complexID] = []
        complexOrder.append(row.complexID)
      }
      grouped[row.complexID, default: []].append(row)
    }

    return try complexOrder.map { complexID in
      guard let members = grouped[complexID], !members.isEmpty else {
        throw SnapshotError.emptyComplex(complexID)
      }
      let routeSet = Set(members.flatMap { $0.daytimeRoutes.split(whereSeparator: \.isWhitespace).map(String.init) })
      let unknownRoutes = routeSet.subtracting(routeOrder)
      guard unknownRoutes.isEmpty else {
        throw SnapshotError.unknownRoutes(unknownRoutes.sorted())
      }
      let routeList = routeOrder.filter(routeSet.contains)
      let nameCounts = Dictionary(grouping: members, by: \.stopName).mapValues(\.count)
      let name = members.map(\.stopName).first { candidate in
        nameCounts[candidate] == nameCounts.values.max()
      } ?? members[0].stopName

      return SubwayStation(
        id: complexID,
        name: name,
        routes: routeList,
        latitude: members.map(\.latitude).reduce(0, +) / Double(members.count),
        longitude: members.map(\.longitude).reduce(0, +) / Double(members.count)
      )
    }
  }

  public static func nearest(
    to coordinate: GeoCoordinate,
    stations: [SubwayStation],
    limit: Int = 3
  ) -> [NearbySubwayStation] {
    guard limit > 0 else { return [] }
    return stations.compactMap { station in
      let distance = distanceMeters(from: coordinate, to: station.coordinate)
      guard distance <= maximumWalkingDistanceMeters else { return nil }
      return NearbySubwayStation(station: station, distanceMeters: distance)
    }
    .sorted {
      if $0.distanceMeters == $1.distanceMeters { return $0.station.name < $1.station.name }
      return $0.distanceMeters < $1.distanceMeters
    }
    .prefix(limit)
    .map { $0 }
  }

  private static func distanceMeters(from first: GeoCoordinate, to second: GeoCoordinate) -> Double {
    // Mean Earth radius, in meters, for the haversine great-circle distance.
    let earthRadiusMeters = 6_371_000.0
    let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
    let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
    let firstLatitude = first.latitude * .pi / 180
    let secondLatitude = second.latitude * .pi / 180
    let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
      + cos(firstLatitude) * cos(secondLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
    return 2 * earthRadiusMeters * atan2(sqrt(haversine), sqrt(1 - haversine))
  }

  private struct StationSnapshot: Decodable {
    let sourceURL: URL
    let fetchedAt: String
    let stations: [StationRow]
  }

  public struct StationRow: Decodable, Sendable {
    public let complexID: String
    public let stopName: String
    public let daytimeRoutes: String
    public let latitude: Double
    public let longitude: Double

    public init(complexID: String, stopName: String, daytimeRoutes: String, latitude: Double, longitude: Double) {
      self.complexID = complexID
      self.stopName = stopName
      self.daytimeRoutes = daytimeRoutes
      self.latitude = latitude
      self.longitude = longitude
    }

    enum CodingKeys: String, CodingKey {
      case complexID = "complex_id"
      case stopName = "stop_name"
      case daytimeRoutes = "daytime_routes"
      case latitude = "gtfs_latitude"
      case longitude = "gtfs_longitude"
    }
  }

  private enum SnapshotError: LocalizedError {
    case resourceMissing
    case emptyComplex(String)
    case unknownRoutes([String])

    var errorDescription: String? {
      switch self {
      case .resourceMissing:
        "The bundled MTA station snapshot is missing."
      case let .emptyComplex(complexID):
        "MTA station complex \(complexID) has no station rows."
      case let .unknownRoutes(routes):
        "The MTA station snapshot includes unknown subway routes: \(routes.joined(separator: ", "))."
      }
    }
  }
}
