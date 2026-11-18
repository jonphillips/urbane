import SwiftUI

struct PeopleSettingsSheet: View {
  let model: UrbaneMapModel
  @Environment(\.dismiss) private var dismiss
  @AppStorage("urbane.thisIsMe") private var thisIsMe = ""

  var body: some View {
    NavigationStack {
      Form {
        SyncAndShareSettingsSection(mapModel: model)
        if let message = model.message {
          Section { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        Section {
          if model.people.isEmpty {
            Text("People are being set up.").foregroundStyle(.secondary)
          } else {
            VStack(alignment: .leading, spacing: 6) {
              Text("This is me")
              Picker("This is me", selection: $thisIsMe) {
                Text("Choose a person").tag("")
                ForEach(model.people) { person in
                  Text(person.displayName).tag(person.id.uuidString)
                }
              }
              .labelsHidden()
              .onChange(of: thisIsMe) { _, value in
                model.bindCurrentPerson(id: UUID(uuidString: value))
              }
            }
          }
        } header: {
          Text("People")
        } footer: {
          Text("This choice is saved on this device. Change it when the other person is rating buildings.")
        }
      }
      .navigationTitle("People & identity")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}
