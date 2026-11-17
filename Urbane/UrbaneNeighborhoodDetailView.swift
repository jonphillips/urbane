import MapKit
import Charts
import SQLiteData
import SwiftUI
import UrbaneCore
import UrbaneSchema

struct NeighborhoodDetailSheet: View {
  let neighborhood: Neighborhood
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @State private var chapter: String
  @State private var centerLatitude = ""
  @State private var centerLongitude = ""
  @State private var latitudeSpan: Double
  @State private var longitudeSpan: Double
  @State private var query = ""
  @State private var results: [PlaceMatch] = []
  @State private var error: String?
  @State private var camera: MapCameraPosition

  init(neighborhood: Neighborhood, model: UrbaneMapModel) {
    self.neighborhood = neighborhood
    self.model = model
    _chapter = State(initialValue: neighborhood.chapter)
    _centerLatitude = State(initialValue: String(neighborhood.centerLatitude))
    _centerLongitude = State(initialValue: String(neighborhood.centerLongitude))
    _latitudeSpan = State(initialValue: max(neighborhood.latitudeSpan, 0.01))
    _longitudeSpan = State(initialValue: max(neighborhood.longitudeSpan, 0.01))
    _camera = State(initialValue: .region(MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: neighborhood.centerLatitude, longitude: neighborhood.centerLongitude),
      span: MKCoordinateSpan(latitudeDelta: max(neighborhood.latitudeSpan, 0.01), longitudeDelta: max(neighborhood.longitudeSpan, 0.01))
    )))
  }

  var body: some View {
    NavigationStack {
      List {
        Section("Chapter") {
          TextEditor(text: $chapter)
            .frame(minHeight: 180)
            .accessibilityLabel("Neighborhood chapter")
            .onChange(of: chapter) { _, value in model.updateNeighborhoodChapter(neighborhood, chapter: value) }
        }

        Section("Places") {
          let vignettes = model.neighborhoodVignettes
            .filter { $0.neighborhoodID == neighborhood.id }
            .sorted { $0.sortOrder < $1.sortOrder }
          if vignettes.isEmpty {
            Text("No places added yet.").foregroundStyle(.secondary)
          } else {
            ForEach(vignettes) { vignette in
              LookAroundGalleryPage(neighborhoodVignette: vignette)
            }
          }
        }

        Section("Buildings") {
          let buildings = model.buildings.filter { $0.neighborhoodID == neighborhood.id }
          if buildings.isEmpty {
            Text("No buildings in this neighborhood yet.").foregroundStyle(.secondary)
          } else {
            ForEach(buildings) { building in
              NavigationLink {
                BuildingDetailSheet(building: building, model: model)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(building.name)
                  Text(building.address).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }

        Section("Neighborhood region") {
          TextField("Search address or place", text: $query)
            .textInputAutocapitalization(.words)
          Button("Search location") { Task { await search() } }.disabled(query.isEmpty)
          ForEach(results) { place in
            Button("Use \(place.name) · \(place.address)") {
              centerLatitude = String(place.latitude)
              centerLongitude = String(place.longitude)
              camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
              ))
            }
          }
          MapReader { proxy in
            Map(position: $camera) {
              MapCircle(
                center: CLLocationCoordinate2D(
                  latitude: Double(centerLatitude) ?? neighborhood.centerLatitude,
                  longitude: Double(centerLongitude) ?? neighborhood.centerLongitude
                ),
                radius: max(latitudeSpan, longitudeSpan) * 55_500
              )
              .foregroundStyle(.blue.opacity(0.10))
              .stroke(.blue.opacity(0.35), lineWidth: 1)
              Annotation("Center", coordinate: CLLocationCoordinate2D(
                latitude: Double(centerLatitude) ?? neighborhood.centerLatitude,
                longitude: Double(centerLongitude) ?? neighborhood.centerLongitude
              )) {
                Image(systemName: "mappin.and.ellipse").font(.title).foregroundStyle(.red)
              }.annotationTitles(.hidden)
            }
            .onTapGesture(coordinateSpace: .local) { point in
              guard let coordinate = proxy.convert(point, from: .local) else { return }
              centerLatitude = String(coordinate.latitude)
              centerLongitude = String(coordinate.longitude)
            }
            .frame(height: 210)
          }
          Text("Search again or tap the map to move the center.")
            .font(.footnote).foregroundStyle(.secondary)
          Stepper("North–south span: \(latitudeSpan, specifier: "%.2f")°", value: $latitudeSpan, in: 0.01...0.20, step: 0.01)
          Stepper("East–west span: \(longitudeSpan, specifier: "%.2f")°", value: $longitudeSpan, in: 0.01...0.20, step: 0.01)
          if let error { Text(error).foregroundStyle(.red) }
        }

        Section("Rent band") {
          let rents = model.neighborhoodRents.filter { $0.neighborhoodID == neighborhood.id }
            .sorted { $0.month < $1.month }
          if let latest = rents.last {
            Text(latest.median2BRRent, format: .currency(code: "USD").precision(.fractionLength(0)))
              .font(.title3.weight(.semibold))
            Text("\(latest.month) · \(latest.sourceLabel)").font(.caption).foregroundStyle(.secondary)
            NeighborhoodRentSparkline(rents: Array(rents.suffix(12)))
              .frame(height: 54)
              .accessibilityLabel("12 month two bedroom median asking rent trend")
          } else {
            Label("Import dated 2 bedroom asking rents from Settings.", systemImage: "calendar")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(neighborhood.name)
      .onChange(of: centerLatitude) { _, _ in saveRegion() }
      .onChange(of: centerLongitude) { _, _ in saveRegion() }
      .onChange(of: latitudeSpan) { _, _ in saveRegion() }
      .onChange(of: longitudeSpan) { _, _ in saveRegion() }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }

  private func search() async {
    do {
      results = try await model.search("\(query), New York, NY")
      if results.isEmpty { error = "No matching place found. Tap the map to set the center." }
      else { error = nil }
    } catch { self.error = error.localizedDescription }
  }

  private func saveRegion() {
    guard let latitude = Double(centerLatitude), let longitude = Double(centerLongitude),
          (-90...90).contains(latitude), (-180...180).contains(longitude) else {
      return
    }
    camera = .region(MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
    ))
    model.updateNeighborhoodRegion(
      neighborhood, latitude: latitude, longitude: longitude,
      latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan
    )
    error = nil
  }
}

private struct NeighborhoodRentSparkline: View {
  let rents: [NeighborhoodRent]

  var body: some View {
    Chart {
      ForEach(Array(rents.enumerated()), id: \.element.id) { item in
        LineMark(x: .value("Month", item.offset), y: .value("Rent", item.element.median2BRRent))
          .foregroundStyle(.blue)
        PointMark(x: .value("Month", item.offset), y: .value("Rent", item.element.median2BRRent))
          .foregroundStyle(.blue)
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: .automatic(includesZero: false))
  }
}
