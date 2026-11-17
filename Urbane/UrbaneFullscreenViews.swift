import MapKit
import SwiftUI
import UIKit
import UrbaneSchema

struct FullScreenPostcardMap: View {
  let building: Building
  @Environment(\.dismiss) private var dismiss
  @State private var camera: MapCameraPosition

  init(building: Building) {
    self.building = building
    _camera = State(initialValue: .camera(MapCamera(
      centerCoordinate: CLLocationCoordinate2D(latitude: building.latitude, longitude: building.longitude),
      distance: 350, heading: 30, pitch: 55
    )))
  }

  var body: some View {
    NavigationStack {
      Map(position: $camera) {}
        .mapStyle(.hybrid(elevation: .realistic))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(building.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
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
