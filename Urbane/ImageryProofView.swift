import SwiftUI
import UIKit

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
    SeedAddress(id: 4, title: "189 North 12th Street", address: "189 North 12th Street, Brooklyn, NY 11249"),
    SeedAddress(id: 5, title: "5-26 47th Avenue", address: "5-26 47th Avenue, Long Island City, NY 11101"),
    SeedAddress(id: 6, title: "4545 Center Boulevard", address: "4545 Center Boulevard, Long Island City, NY 11109"),
    SeedAddress(id: 7, title: "46-30 Center Boulevard", address: "46-30 Center Boulevard, Long Island City, NY 11109"),
    SeedAddress(id: 8, title: "41-41 27th Street", address: "41-41 27th Street, Long Island City, NY 11101"),
  ]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 20) {
          Text("MapKit matches, Look Around scenes, realistic 3D maps, and hybrid alternatives for each address.")
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
  private let client = UrbaneImageryClient()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(seed.title).font(.headline)
        Text(seed.address).font(.subheadline).foregroundStyle(.secondary)
      }
      if let imagery {
        VStack(alignment: .leading, spacing: 3) {
          Text("MapKit match: \(imagery.matchedName ?? "No match")")
          if let latitude = imagery.matchedLatitude, let longitude = imagery.matchedLongitude {
            Text(String(format: "%.5f, %.5f", latitude, longitude))
          }
          Text(imagery.matchKind ?? imagery.searchError ?? "")
            .foregroundStyle(.secondary)
        }
        .font(.caption)
      }
      HStack(alignment: .top, spacing: 12) {
        ImageryProofImage(
          title: "Look Around", image: imagery?.lookAround,
          error: imagery?.lookAroundError ?? imagery?.searchError
        )
        ImageryProofImage(
          title: "Realistic 3D", image: imagery?.standard3D,
          error: imagery?.standard3DError ?? imagery?.searchError
        )
        ImageryProofImage(
          title: "Realistic Hybrid", image: imagery?.hybrid3D,
          error: imagery?.hybrid3DError ?? imagery?.searchError
        )
      }
    }
    .task {
      imagery = await client.preview(placeName: seed.title, address: seed.address)
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
