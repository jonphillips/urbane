import SwiftUI

enum BuildingDetailChrome {
  case sheet
  case panel(onClose: () -> Void)

  var isPanel: Bool {
    if case .panel = self { true } else { false }
  }
}

struct BuildingDetailActionsMenu: View {
  let hasWebsite: Bool
  let onChooseHero: () -> Void
  let onEditLinks: () -> Void

  var body: some View {
    Menu {
      Button(hasWebsite ? "Choose hero image" : "Choose hero image — Add a website in Edit links", systemImage: "photo", action: onChooseHero)
        .disabled(!hasWebsite)
      Button("Edit links", systemImage: "link", action: onEditLinks)
    } label: {
      Image(systemName: "ellipsis")
    }
  }
}

struct BuildingDetailPanelHeader: View {
  let buildingName: String
  let hasWebsite: Bool
  let onChooseHero: () -> Void
  let onEditLinks: () -> Void
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(buildingName).font(.headline).lineLimit(1)
      Spacer(minLength: 0)
      BuildingDetailActionsMenu(
        hasWebsite: hasWebsite,
        onChooseHero: onChooseHero,
        onEditLinks: onEditLinks
      )
      Button("Close", systemImage: "xmark", action: onClose)
        .labelStyle(.iconOnly)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
