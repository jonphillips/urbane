import Testing
import UrbaneCore
import UrbaneSchema

@Suite struct SubwayStationsTests {
  @Test func bundledStationsGroupTimesSquareAndEveryRouteHasAPaletteColor() throws {
    let stations = try SubwayStations.load()
    let timesSquare = try #require(stations.first { $0.id == "611" })

    #expect(stations.count == 445)
    #expect(timesSquare.name == "Times Sq-42 St")
    #expect(timesSquare.routes == ["1", "2", "3", "7", "A", "C", "E", "N", "Q", "R", "S", "W"])

    let routesInSnapshot = Set(stations.flatMap(\.routes))
    #expect(routesInSnapshot.count == 24)
    #expect(routesInSnapshot.isSubset(of: Set(SubwayStations.lineStyles.keys)))
    #expect(SubwayStations.lineStyles["N"]?.textHex == 0x000000)
    #expect(SubwayStations.lineStyles["Q"]?.textHex == 0x000000)
    #expect(SubwayStations.lineStyles["R"]?.textHex == 0x000000)
    #expect(SubwayStations.lineStyles["W"]?.textHex == 0x000000)
  }

  @Test func nearestStationsAreSortedLimitedAndCutOffAtEightHundredMeters() {
    let origin = GeoCoordinate(latitude: 40, longitude: -73)
    let stations = [
      station("far", latitudeOffset: 0.0073),
      station("third", latitudeOffset: 0.0060),
      station("first", latitudeOffset: 0.0020),
      station("second", latitudeOffset: 0.0040),
    ]

    let nearest = SubwayStations.nearest(to: origin, stations: stations)
    #expect(nearest.map(\.station.id) == ["first", "second", "third"])
    #expect(nearest.allSatisfy { $0.distanceMeters <= SubwayStations.maximumWalkingDistanceMeters })
    #expect(nearest.first?.approximateWalkMinutes == 3)
    #expect(SubwayStations.nearest(to: origin, stations: stations, limit: 1).map(\.station.id) == ["first"])
    #expect(SubwayStations.nearest(to: origin, stations: stations, limit: 0).isEmpty)

    let cutoffStations = [
      station("inside", latitudeOffset: latitudeOffset(forMeters: SubwayStations.maximumWalkingDistanceMeters - 1)),
      station("outside", latitudeOffset: latitudeOffset(forMeters: SubwayStations.maximumWalkingDistanceMeters + 1)),
    ]
    let withinCutoff = SubwayStations.nearest(to: origin, stations: cutoffStations)
    #expect(withinCutoff.map(\.station.id) == ["inside"])
    #expect(withinCutoff.first?.distanceMeters ?? .infinity < SubwayStations.maximumWalkingDistanceMeters)
  }

  private func station(_ id: String, latitudeOffset: Double) -> SubwayStation {
    SubwayStation(
      id: id,
      name: id,
      routes: ["L"],
      latitude: 40 + latitudeOffset,
      longitude: -73
    )
  }

  private func latitudeOffset(forMeters meters: Double) -> Double {
    // Convert a north–south great-circle distance using the same mean Earth radius as the loader.
    meters / 6_371_000 * 180 / .pi
  }
}
