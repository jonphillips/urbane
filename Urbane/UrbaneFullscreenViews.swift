import MapKit
import SwiftUI
import UIKit
import UrbaneCore
import UrbaneSchema

struct FullScreenPostcardMap: View {
  let building: Building
  @Environment(\.dismiss) private var dismiss
  @State private var camera: MapCameraPosition
  @State private var stationRegion: MKCoordinateRegion?
  @State private var stationCameraDistance = 350.0

  init(building: Building) {
    self.building = building
    _camera = State(initialValue: .camera(MapCamera(
      centerCoordinate: CLLocationCoordinate2D(latitude: building.latitude, longitude: building.longitude),
      distance: 350, heading: 30, pitch: 55
    )))
  }

  var body: some View {
    NavigationStack {
      Map(position: $camera) {
        ForEach(visibleStations) { station in
          Annotation(station.name, coordinate: CLLocationCoordinate2D(
            latitude: station.latitude,
            longitude: station.longitude
          )) {
            SubwayStationMarker(
              station: station,
              showsName: stationCameraDistance <= SubwayStationVisibility.maximumNameCameraDistance
            )
          }
          .annotationTitles(.hidden)
        }
      }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excluding([.publicTransport])))
        .onMapCameraChange(frequency: .continuous) { context in
          stationRegion = context.region
          stationCameraDistance = context.camera.distance
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
          if let stationLoadError {
            Text("Subway stations couldn't be loaded: \(stationLoadError)")
              .font(.footnote).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
              .padding()
          }
        }
        .navigationTitle(building.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
  }

  private var visibleStations: [SubwayStation] {
    guard stationCameraDistance <= SubwayStationVisibility.maximumCameraDistance,
          let stationRegion,
          case let .success(stations) = SubwayStations.bundled else { return [] }
    return stations.filter { stationRegion.contains($0) }
  }

  private var stationLoadError: String? {
    guard case let .failure(error) = SubwayStations.bundled else { return nil }
    return error.localizedDescription
  }
}

struct FullScreenHeroImage: View {
  let image: UIImage
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
    .presentationBackground(.black)
  }
}
