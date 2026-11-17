import SwiftUI

struct RejectionReasonEditor: View {
  @Binding var reasonDraft: String
  let onCancel: () -> Void
  let onSave: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        VStack(alignment: .leading, spacing: 6) {
          Text("Reason")
          TextField("Why pass on this building?", text: $reasonDraft, axis: .vertical)
            .lineLimit(3...6)
        }
      }
      .navigationTitle("Pass on building")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: onSave)
            .disabled(reasonDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
