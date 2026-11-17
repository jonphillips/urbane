import SwiftUI
import UrbaneCore
import UrbaneSchema

struct BuildingLinksEditor: View {
  let building: Building
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @State private var websiteURL: String
  @State private var streetEasyURL: String

  init(building: Building, model: UrbaneMapModel) {
    self.building = building
    self.model = model
    _websiteURL = State(initialValue: building.websiteURL ?? "")
    _streetEasyURL = State(initialValue: building.streetEasyURL ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          linkField("Website", value: $websiteURL, field: .website)
          linkField("StreetEasy", value: $streetEasyURL, field: .streetEasy)
        } footer: {
          Text("Leave a field empty to clear its link.")
        }
      }
      .navigationTitle("Edit links")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(websiteError != nil || streetEasyError != nil)
        }
      }
    }
  }

  private var websiteError: String? { validationError(for: websiteURL, field: .website) }
  private var streetEasyError: String? { validationError(for: streetEasyURL, field: .streetEasy) }

  private func linkField(_ title: String, value: Binding<String>, field: BuildingLinkField) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline.weight(.medium))
      TextField("https://…", text: value)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityLabel(title)
      if let error = validationError(for: value.wrappedValue, field: field) {
        Text(error).font(.footnote).foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private func validationError(for value: String, field: BuildingLinkField) -> String? {
    do {
      _ = try BuildingLinkValidator.validate(value, for: field)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  private func save() {
    guard let website = try? BuildingLinkValidator.validate(websiteURL, for: .website),
          let streetEasy = try? BuildingLinkValidator.validate(streetEasyURL, for: .streetEasy) else { return }
    model.updateBuildingLinks(building, websiteURL: website, streetEasyURL: streetEasy)
    dismiss()
  }
}
