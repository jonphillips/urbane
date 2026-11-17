import MapKit
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers
import UrbaneCore
import UrbaneSchema

struct MapHomeView: View {
  @State private var model = UrbaneMapModel()
  @State private var showingNeighborhood = false
  @State private var showingBuilding = false
  @State private var showingImport = false
  @State private var showingRentCSVImporter = false
  @State private var rentImportNotice: String?
  @State private var selectedBuilding: Building?
  @State private var selectedNeighborhood: Neighborhood?
  @State private var camera: MapCameraPosition = .region(Self.initialRegion)
  @State private var stationRows: [SubwayStation] = []
  @State private var stationRegion: MKCoordinateRegion?
  @State private var stationCameraDistance = Double.infinity
  @State private var stationLoadError: String?

  @FetchAll(Neighborhood.order(by: \.name)) private var neighborhoods
  @FetchAll(Building.order(by: \.name)) private var buildings

  var body: some View {
    NavigationStack {
      Map(position: $camera) {
        ForEach(neighborhoods) { neighborhood in
          MapCircle(
            center: CLLocationCoordinate2D(latitude: neighborhood.centerLatitude, longitude: neighborhood.centerLongitude),
            radius: max(neighborhood.latitudeSpan, neighborhood.longitudeSpan) * 55_500
          )
          .foregroundStyle(.blue.opacity(0.10))
          .stroke(.blue.opacity(0.35), lineWidth: 1)
          Annotation(neighborhood.name, coordinate: CLLocationCoordinate2D(latitude: neighborhood.centerLatitude, longitude: neighborhood.centerLongitude)) {
            Button { selectedNeighborhood = neighborhood } label: {
              Text(neighborhood.name).font(.caption.weight(.semibold)).padding(5).background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
          }
          .annotationTitles(.hidden)
        }
        ForEach(buildings) { building in
          Annotation(building.name, coordinate: CLLocationCoordinate2D(latitude: building.latitude, longitude: building.longitude)) {
            Button { selectedBuilding = building } label: {
              Image(systemName: "building.2.fill")
                .font(.body.weight(.semibold)).padding(9)
                .foregroundStyle(.white).background(color(for: building.status), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(building.name)
          }
        }
        ForEach(visibleStations) { station in
          Annotation(station.name, coordinate: CLLocationCoordinate2D(
            latitude: station.latitude,
            longitude: station.longitude
          )) {
            SubwayStationMarker(station: station, showsName: true)
          }
          .annotationTitles(.hidden)
        }
      }
      .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excluding([.publicTransport])))
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
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Menu("Debug", systemImage: "ladybug") {
            NavigationLink("Imagery proof") { ImageryProofView() }
          }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Neighborhood", systemImage: "map") { showingNeighborhood = true }
          Button("Building", systemImage: "plus") { showingBuilding = true }
          Button("Import", systemImage: "doc.on.clipboard") { showingImport = true }
          Menu("Settings", systemImage: "gearshape") {
            Button("Import neighborhood rents", systemImage: "tablecells") { showingRentCSVImporter = true }
          }
        }
      }
      .sheet(isPresented: $showingNeighborhood) { AddNeighborhoodSheet(model: model) }
      .sheet(isPresented: $showingBuilding) { AddBuildingSheet(model: model) }
      .sheet(isPresented: $showingImport) { ChatImportSheet(model: model) }
      .fileImporter(isPresented: $showingRentCSVImporter, allowedContentTypes: [.commaSeparatedText]) { result in
        do {
          let url = try result.get()
          let didStart = url.startAccessingSecurityScopedResource()
          defer { if didStart { url.stopAccessingSecurityScopedResource() } }
          model.importNeighborhoodRents(try Data(contentsOf: url))
          rentImportNotice = model.rentImportMessage ?? model.rentImportError
        } catch {
          rentImportNotice = error.localizedDescription
        }
      }
      .alert("Neighborhood rent import", isPresented: Binding(
        get: { rentImportNotice != nil }, set: { if !$0 { rentImportNotice = nil } }
      )) {
        Button("OK") { rentImportNotice = nil }
      } message: { Text(rentImportNotice ?? "") }
      .sheet(item: $selectedBuilding) { building in
        NavigationStack {
          BuildingDetailSheet(building: building, model: model)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { selectedBuilding = nil }
              }
            }
        }
        .presentationSizing(.page)
      }
      .sheet(item: $selectedNeighborhood) { neighborhood in
        NeighborhoodDetailSheet(neighborhood: neighborhood, model: model)
          .presentationSizing(.page)
      }
      .task {
        model.bootstrap()
        do { stationRows = try SubwayStations.load() }
        catch { stationLoadError = error.localizedDescription }
      }
    }
  }

  private func color(for status: BuildingStatus) -> Color {
    switch status {
    case .exploring: .blue
    case .watching: .orange
    case .tourCandidate: .green
    case .rejected: .gray
    }
  }

  private var visibleStations: [SubwayStation] {
    guard stationCameraDistance <= SubwayStationVisibility.maximumCameraDistance,
          let stationRegion else { return [] }
    return stationRows.filter { stationRegion.contains($0) }
  }

  private static let initialRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.96),
    span: MKCoordinateSpan(latitudeDelta: 0.13, longitudeDelta: 0.18)
  )
}

private struct AddNeighborhoodSheet: View {
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var results: [PlaceMatch] = []
  @State private var selected: PlaceMatch?
  @State private var busy = false
  @State private var latitudeSpan = 0.02
  @State private var longitudeSpan = 0.02
  @State private var centerLatitude = ""
  @State private var centerLongitude = ""
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        TextField("Neighborhood name", text: $name)
        Button("Search region") { Task { await findRegion() } }.disabled(name.isEmpty || busy)
        ForEach(results) { place in
          Button {
            selected = place
            latitudeSpan = 0.02
            longitudeSpan = 0.02
            centerLatitude = String(place.latitude)
            centerLongitude = String(place.longitude)
          } label: {
            Label("\(place.name) · \(place.address)", systemImage: selected?.id == place.id ? "checkmark.circle.fill" : "mappin")
          }
        }
        if selected != nil {
          TextField("Center latitude", text: $centerLatitude).keyboardType(.decimalPad)
          TextField("Center longitude", text: $centerLongitude).keyboardType(.decimalPad)
          Stepper("North–south span: \(latitudeSpan, specifier: "%.2f")°", value: $latitudeSpan, in: 0.01...0.20, step: 0.01)
          Stepper("East–west span: \(longitudeSpan, specifier: "%.2f")°", value: $longitudeSpan, in: 0.01...0.20, step: 0.01)
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Add neighborhood")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let selected, let latitude = Double(centerLatitude), let longitude = Double(centerLongitude) {
              let adjusted = PlaceMatch(name: selected.name, address: selected.address, latitude: latitude, longitude: longitude, mapItemIdentifier: selected.mapItemIdentifier)
              model.addNeighborhood(name: name, match: adjusted, latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan)
              dismiss()
            }
          }.disabled(selected == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }

  private func findRegion() async {
    busy = true
    defer { busy = false }
    do { results = try await model.search("\(name), New York, NY") }
    catch { self.error = error.localizedDescription }
  }
}

private struct AddBuildingSheet: View {
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @FetchAll(Neighborhood.order(by: \.name)) private var neighborhoods
  @State private var neighborhoodID: UUID?
  @State private var query = ""
  @State private var name = ""
  @State private var address = ""
  @State private var results: [PlaceMatch] = []
  @State private var selected: PlaceMatch?
  @State private var streetEasyURL: String?
  @State private var websiteURL: String?
  @State private var error: String?
  @State private var manualLatitude = "40.7128"
  @State private var manualLongitude = "-73.9400"
  @State private var pinCamera: MapCameraPosition = .region(MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.94),
    span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
  ))

  var body: some View {
    NavigationStack {
      Form {
        Picker("Neighborhood", selection: $neighborhoodID) {
          ForEach(neighborhoods) { Text($0.name).tag(Optional($0.id)) }
        }
        TextField("Name, address, or building URL", text: $query)
          .textInputAutocapitalization(.never).keyboardType(.URL)
        Button("Search in New York City") { Task { await search() } }.disabled(query.isEmpty)
        ForEach(results) { place in
          Button {
            selected = place
            if name.isEmpty { name = place.name }
            if address.isEmpty { address = place.address }
          } label: {
            Label("\(place.name) · \(place.address)", systemImage: selected?.id == place.id ? "checkmark.circle.fill" : "mappin")
          }
        }
        TextField("Building name", text: $name)
        TextField("Address", text: $address)
        if let neighborhood = neighborhoods.first(where: { $0.id == neighborhoodID }) {
          MapReader { proxy in
            Map(position: $pinCamera) {
              if let latitude = Double(manualLatitude), let longitude = Double(manualLongitude) {
                Annotation("Pin", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) { Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red) }
              }
            }
            .onTapGesture(coordinateSpace: .local) { point in
              if let coordinate = proxy.convert(point, from: .local) {
                manualLatitude = String(coordinate.latitude)
                manualLongitude = String(coordinate.longitude)
                chooseManualPin()
              }
            }
            .frame(height: 200)
            .onAppear {
              pinCamera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: neighborhood.centerLatitude, longitude: neighborhood.centerLongitude),
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
              ))
              manualLatitude = String(neighborhood.centerLatitude)
              manualLongitude = String(neighborhood.centerLongitude)
            }
          }
          Text("Tap the map to place or move a pin.").font(.footnote).foregroundStyle(.secondary)
          HStack {
            TextField("Latitude", text: $manualLatitude).keyboardType(.decimalPad)
            TextField("Longitude", text: $manualLongitude).keyboardType(.decimalPad)
          }
          Button("Use this pin") { chooseManualPin() }
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Add building")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if let neighborhoodID, let selected {
              model.addBuilding(neighborhoodID: neighborhoodID, name: name, address: address, match: selected, streetEasyURL: streetEasyURL, websiteURL: websiteURL)
              dismiss()
            }
          }.disabled(neighborhoodID == nil || selected == nil || name.isEmpty || address.isEmpty)
        }
      }
      .onChange(of: query) { _, value in parseURL(value) }
    }
  }

  private func parseURL(_ value: String) {
    guard let slug = BuildingURLSlug.parse(value) else { return }
    name = slug.name
    address = slug.address
    if URL(string: value)?.host?.contains("streeteasy") == true { streetEasyURL = value }
    else { websiteURL = value }
  }

  private func search() async {
    do {
      let text = BuildingURLSlug.parse(query).map { "\($0.name), \($0.address), New York, NY" } ?? "\(query), New York, NY"
      results = try await model.search(text)
      if results.count == 1 { selected = results[0] }
      if results.isEmpty { error = "No match. Add a neighborhood first, then search again or choose a pin location." }
    } catch { self.error = error.localizedDescription }
  }

  private func chooseManualPin() {
    guard let latitude = Double(manualLatitude), let longitude = Double(manualLongitude) else { return }
    selected = PlaceMatch(name: name, address: address, latitude: latitude, longitude: longitude, mapItemIdentifier: nil)
  }
}

struct BuildingLocationSheet: View {
  let building: Building
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @State private var results: [PlaceMatch] = []
  @State private var error: String?
  @State private var latitude = ""
  @State private var longitude = ""

  var body: some View {
    NavigationStack {
      List {
        Button("Re-run address search") { Task { await search() } }
        ForEach(results) { place in
          Button("Use \(place.name) · \(place.address)") { model.fixLocation(building, match: place); dismiss() }
        }
        Section("Move pin by hand") {
          TextField("Latitude", text: $latitude).keyboardType(.decimalPad)
          TextField("Longitude", text: $longitude).keyboardType(.decimalPad)
          Button("Use this coordinate") {
            if let lat = Double(latitude), let lon = Double(longitude) {
              model.fixLocation(building, match: PlaceMatch(name: building.name, address: building.address, latitude: lat, longitude: lon, mapItemIdentifier: nil))
              dismiss()
            }
          }
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Fix location")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
      .task { latitude = String(building.latitude); longitude = String(building.longitude); await search() }
    }
  }

  private func search() async {
    do { results = try await model.search("\(building.name), \(building.address), New York, NY") }
    catch { self.error = error.localizedDescription }
  }
}
