import SwiftUI

struct TabGroupEditorRequest: Identifiable {
    let id = UUID()
    var group: TabGroup? = nil
    var tabID: UUID? = nil
}

struct TabGroupEditor: View {
    let browser: BrowserModel
    let request: TabGroupEditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: TabGroupColor = .blue
    @FocusState private var isNameFocused: Bool

    private var validName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.group == nil ? "New Tab Group" : "Edit Tab Group").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit { if validName { save() } }
            HStack {
                Text("Color")
                Spacer()
                Circle().fill(color.tint).frame(width: 12, height: 12).accessibilityHidden(true)
                Picker("Color", selection: $color) {
                    ForEach(TabGroupColor.allCases) { color in Text(color.title).tag(color) }
                }
                .labelsHidden().frame(width: 150)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.group == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction).disabled(!validName)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            name = request.group?.name ?? ""
            color = request.group?.color ?? .blue
            isNameFocused = true
        }
    }

    private func save() {
        guard validName else { return }
        if let group = request.group {
            browser.updateGroup(group.id, name: name, color: color)
        } else {
            browser.createGroup(name: name, color: color, tabID: request.tabID)
        }
        dismiss()
    }
}
