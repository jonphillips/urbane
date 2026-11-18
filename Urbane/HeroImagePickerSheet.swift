import SwiftUI

struct HeroImagePickerSheet: View {
  let imageCandidates: [URL]
  let onSelect: (URL) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
          ForEach(Array(imageCandidates.prefix(20)), id: \.absoluteString) { url in
            Button {
              dismiss()
              onSelect(url)
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                AsyncImage(url: url) { phase in
                  if let image = phase.image {
                    image.resizable().scaledToFill()
                  } else if phase.error != nil {
                    ContentUnavailableView("Image unavailable", systemImage: "photo")
                  } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                  }
                }
                .frame(height: 132).frame(maxWidth: .infinity)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                Text(url.lastPathComponent.isEmpty ? (url.host ?? "Image") : url.lastPathComponent)
                  .font(.caption).lineLimit(1).foregroundStyle(.secondary)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding()
      }
      .navigationTitle("Choose hero image")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }
}
