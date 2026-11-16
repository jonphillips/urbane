import SwiftUI
import UIKit
import UrbaneImaging

private struct SeedAddress: Identifiable {
  let id: Int
  let title: String
  let address: String
}

struct ImageryProofView: View {
  private let seeds = [
    SeedAddress(id: 1, title: "One North Fourth", address: "1 North 4th Place, Brooklyn, NY 11249"),
    SeedAddress(id: 2, title: "420 Kent Avenue", address: "420 Kent Avenue, Brooklyn, NY 11249"),
    SeedAddress(id: 3, title: "The Oosten", address: "429 Kent Avenue, Brooklyn, NY 11249"),
    SeedAddress(id: 4, title: "One Blue Slip", address: "1 Blue Slip, Brooklyn, NY 11222"),
    SeedAddress(id: 5, title: "5-26 47th Avenue", address: "5-26 47th Avenue, Long Island City, NY 11101"),
    SeedAddress(id: 6, title: "4545 Center Boulevard", address: "4545 Center Boulevard, Long Island City, NY 11109"),
    SeedAddress(id: 7, title: "The Forge", address: "41-41 27th Street, Long Island City, NY 11101"),
    SeedAddress(id: 8, title: "Court Square", address: "25-01 Jackson Avenue, Long Island City, NY 11101"),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          Text("Look Around scenes and the same angled 3D map view, requested from MapKit for each address.")
            .foregroundStyle(.secondary)
          ForEach(seeds) { seed in
            ImageryProofRow(seed: seed)
          }
        }
        .padding()
      }
      .navigationTitle("Imagery Proof")
    }
  }
}

private struct ImageryProofRow: View {
  let seed: SeedAddress
  @State private var imagery: ImageryPair?
  private let client = UrbaneImageryClient.live

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(seed.title).font(.headline)
        Text(seed.address).font(.subheadline).foregroundStyle(.secondary)
      }
      HStack(alignment: .top, spacing: 12) {
        ImageryProofImage(title: "Look Around", image: imagery?.lookAround, error: imagery?.lookAroundError)
        ImageryProofImage(title: "Angled 3D", image: imagery?.angledMap, error: imagery?.angledMapError)
      }
    }
    .task {
      imagery = await client.preview(seed.address)
    }
  }
}

private struct ImageryProofImage: View {
  let title: String
  let image: UIImage?
  let error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.caption.weight(.semibold))
      Group {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          ContentUnavailableView(error ?? "Loading", systemImage: "map")
        }
      }
      .frame(maxWidth: .infinity)
      .aspectRatio(1.5, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
