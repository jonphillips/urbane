import MapKit
import SwiftUI
import UIKit
import UrbaneCore
import UrbaneSchema

struct BuildingVignetteEditor: View {
  let building: Building
  let model: UrbaneMapModel
  let vignette: BuildingVignette?
  @Environment(\.dismiss) private var dismiss
  @State private var query: String
  @State private var caption: String
  @State private var results: [PlaceMatch] = []
  @State private var selected: PlaceMatch?
  @State private var error: String?
  @State private var scene: MKLookAroundScene?
  @State private var snapshot: UIImage?
  @State private var camera: MapCameraPosition
  private let imageryClient = UrbaneImageryClient()

  init(building: Building, model: UrbaneMapModel, vignette: BuildingVignette?, initialCaption: String = "") {
    self.building = building
    self.model = model
    self.vignette = vignette
    _query = State(initialValue: vignette?.placeName ?? building.address)
    _caption = State(initialValue: vignette?.caption ?? initialCaption)
    _selected = State(initialValue: PlaceMatch(
      name: vignette?.placeName ?? building.name,
      address: vignette?.placeName ?? building.address,
      latitude: vignette?.latitude ?? building.latitude,
      longitude: vignette?.longitude ?? building.longitude,
      mapItemIdentifier: vignette == nil ? building.mapItemIdentifier : vignette?.mapItemIdentifier
    ))
    _camera = State(initialValue: .region(MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: vignette?.latitude ?? building.latitude, longitude: vignette?.longitude ?? building.longitude),
      span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    )))
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Place or corner", text: $query)
        Button("Search nearby places") { Task { await search() } }.disabled(query.isEmpty)
        ForEach(results) { place in
          Button {
            selected = place
            if caption.isEmpty { caption = place.name }
          } label: {
            Label("\(place.name) · \(place.address)", systemImage: selected?.id == place.id ? "checkmark.circle.fill" : "mappin")
          }
        }
        Section("Look Around view") {
          if let snapshot {
            Image(uiImage: snapshot).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
          } else if let scene {
            LookAroundPreview(initialScene: scene, allowsNavigation: true)
              .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 12))
          } else {
            ContentUnavailableView("No still available", systemImage: "binoculars")
              .frame(height: 130)
          }
          MapReader { proxy in
            Map(position: $camera) {
              if let selected {
                Annotation("Viewpoint", coordinate: CLLocationCoordinate2D(latitude: selected.latitude, longitude: selected.longitude)) {
                  Image(systemName: "mappin.and.ellipse").font(.title).foregroundStyle(.red)
                }.annotationTitles(.hidden)
              }
            }
            .onTapGesture(coordinateSpace: .local) { point in
              guard let coordinate = proxy.convert(point, from: .local) else { return }
              selected = PlaceMatch(name: query, address: query, latitude: coordinate.latitude, longitude: coordinate.longitude, mapItemIdentifier: nil)
            }
            .frame(height: 190)
          }
          Text("Choose a nearby map place above, or tap a point on the map.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        TextField("Why this place matters", text: $caption, axis: .vertical)
          .lineLimit(2...5)
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle(vignette == nil ? "Add a place" : "Adjust view")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard let selected else { return }
            if let vignette { model.updateBuildingVignette(vignette, place: selected, caption: caption) }
            else { model.addBuildingVignette(building: building, place: selected, caption: caption) }
            dismiss()
          }.disabled(selected == nil)
        }
      }
      .task { if vignette != nil { await search() } }
      .task(id: selected?.id) { await loadPreview() }
    }
  }

  private func search() async {
    do {
      results = try await model.search("\(query), near \(building.address), New York, NY")
      if results.isEmpty { error = "No match found. You can save the current coordinate and edit it later." }
      else { error = nil }
    } catch { self.error = error.localizedDescription }
  }

  private func loadPreview() async {
    guard let selected else { snapshot = nil; scene = nil; return }
    let image = await imageryClient.lookAroundSnapshot(
      latitude: selected.latitude, longitude: selected.longitude, mapItemIdentifier: selected.mapItemIdentifier
    )
    snapshot = image
    scene = image == nil
      ? await imageryClient.lookAroundScene(latitude: selected.latitude, longitude: selected.longitude, mapItemIdentifier: selected.mapItemIdentifier)
      : nil
  }
}
