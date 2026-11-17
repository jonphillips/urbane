import MapKit
import SwiftUI
import UrbaneCore
import UrbaneSchema

enum SubwayStationVisibility {
  // 0.02° is the default neighborhood span (about 2.22 km north to south); show
  // stations within twice that camera distance to include a neighborhood's edges.
  static let maximumCameraDistance = 0.02 * 111_000 * 2
  // Initial label scale from the S7 review; the iPad gate will tune it for legibility.
  static let maximumNameCameraDistance = 1_500.0
}

extension MKCoordinateRegion {
  func contains(_ station: SubwayStation) -> Bool {
    abs(station.latitude - center.latitude) <= span.latitudeDelta / 2
      && abs(station.longitude - center.longitude) <= span.longitudeDelta / 2
  }
}

struct SubwayStationMarker: View {
  let station: SubwayStation
  let showsName: Bool

  var body: some View {
    HStack(spacing: 5) {
      SubwayRouteBullets(routes: station.routes)
      if showsName {
        Text(station.name)
          .font(.caption.weight(.semibold))
          .fixedSize()
      }
    }
    .padding(5)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().stroke(.primary.opacity(0.28), lineWidth: 1))
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(station.name), subway routes \(station.routes.joined(separator: ", "))")
  }
}

struct SubwayRouteBullets: View {
  let routes: [String]
  var diameter: CGFloat = 21

  var body: some View {
    HStack(spacing: 2) {
      ForEach(routes, id: \.self) { route in
        let style = style(for: route)
        Text(route)
          .font(.system(size: route == "SIR" ? 7 : 9, weight: .bold, design: .rounded))
          .foregroundStyle(color(for: style.textHex))
          .frame(width: diameter, height: diameter)
          .background(color(for: style.fillHex), in: Circle())
      }
    }
    .accessibilityHidden(true)
  }

  private func color(for hex: UInt32) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  private func style(for route: String) -> SubwayLineStyle {
    guard let style = SubwayStations.lineStyles[route] else {
      preconditionFailure("Missing MTA subway line style for route \(route)")
    }
    return style
  }
}

struct BuildingSubwaySection: View {
  let building: Building
  let result: Result<[SubwayStation], Error>

  private var nearbyStations: [NearbySubwayStation] {
    guard case let .success(stations) = result else { return [] }
    return SubwayStations.nearest(
      to: GeoCoordinate(latitude: building.latitude, longitude: building.longitude),
      stations: stations
    )
  }

  var body: some View {
    Section("Subway") {
      if case let .failure(error) = result {
        Text("Subway stations couldn't be loaded: \(error.localizedDescription)")
          .foregroundStyle(.secondary)
      } else if nearbyStations.isEmpty {
        Text("No subway within 800 m").foregroundStyle(.secondary)
      } else {
        ForEach(nearbyStations, id: \.station.id) { nearby in
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              SubwayRouteBullets(routes: nearby.station.routes, diameter: 18)
              Text(nearby.station.name).font(.headline)
            }
            Text("≈ \(nearby.approximateWalkMinutes) min walk · straight line")
              .font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
    }
  }
}
