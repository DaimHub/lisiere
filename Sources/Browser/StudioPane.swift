import SwiftUI

struct StudioPane: View {
    let session: StudioSession
    let close: () -> Void

    @State private var request = ""
    @FocusState private var composerIsFocused: Bool
    @AppStorage("codexModel") private var model = ""

    static let width: CGFloat = 400

    private var library: GeneratedViewLibrary { session.library }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ZStack(alignment: .bottom) {
                if session.showsPreview {
                    PageHost(content: session.webView)
                        .transition(.opacity)
                } else {
                    emptyState
                        .transition(.opacity)
                }
                if let generation = session.generation {
                    ActivityPill(status: generation.status)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: session.showsPreview)
            .animation(.easeOut(duration: 0.2), value: session.generation?.viewID)

            composer
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
        .task { await library.loadModels() }
        .onAppear { composerIsFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Menu {
                Button("New View") { session.select(nil) }
                if !library.views.isEmpty {
                    Divider()
                    ForEach(library.views) { view in
                        Toggle(view.title, isOn: Binding(get: { session.selectedViewID == view.id },
                                                         set: { _ in session.select(view.id) }))
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(session.isGenerating)
            .help("Saved Views")

            Spacer(minLength: 0)

            if let view = session.selectedView {
                Menu {
                    Button("Reload") { session.select(view.id) }
                    Divider()
                    Button("Delete View", role: .destructive) { session.delete(view.id) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(ChromeIconButtonStyle(size: 28))
                .fixedSize()
                .disabled(session.isGenerating)
                .help("View Options")

                Button { session.select(nil) } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(ChromeIconButtonStyle(size: 28))
                .disabled(session.isGenerating)
                .help("New View")
            }

            Button(action: close) {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(ChromeIconButtonStyle(size: 28))
            .help("Hide Studio (⌘\\)")
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(height: 42)
    }

    private var headerTitle: String {
        if let view = session.selectedView { return view.title }
        return session.generation == nil ? "Studio" : "New View"
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: session.isGenerating)
            Text(session.isGenerating ? "Building…" : "What should we build?")
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.2)

            if !session.isGenerating {
                VStack(spacing: 6) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button {
                            session.submit(suggestion, model: selectedModel)
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let suggestions = [
        "A todo list",
        "A pomodoro timer",
        "A habit tracker",
        "A quick notes pad",
    ]

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = session.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { session.errorMessage = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 4)
            } else if let reply = session.lastReply, !session.isGenerating {
                Text(reply)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField(session.selectedView == nil ? "Describe something to build" : "Ask for a change",
                          text: $request, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...6)
                    .focused($composerIsFocused)
                    .onSubmit(send)
                    .disabled(session.isGenerating)

                HStack(spacing: 6) {
                    modelMenu
                    Spacer(minLength: 0)
                    sendButton
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.top, 10)
            .padding(.bottom, 7)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(composerIsFocused ? 0.16 : 0.08), lineWidth: 1)
            }
        }
        .padding(8)
    }

    private var modelMenu: some View {
        Menu {
            if library.models.isEmpty {
                Text("Loading models…")
            }
            ForEach(library.models) { option in
                Toggle(option.displayName, isOn: Binding(get: { selectedModel == option.slug },
                                                         set: { _ in model = option.slug }))
            }
        } label: {
            HStack(spacing: 3) {
                Text(library.models.first { $0.slug == selectedModel }?.displayName ?? selectedModel ?? "Codex")
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Model")
    }

    /// The saved model when Codex still offers it, otherwise Codex's first choice.
    private var selectedModel: String? {
        if library.models.contains(where: { $0.slug == model }) { return model }
        return library.models.first?.slug
    }

    private var sendButton: some View {
        let canSend = !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Button {
            if session.isGenerating { session.cancel() } else { send() }
        } label: {
            Image(systemName: session.isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: session.isGenerating ? 9 : 11, weight: .bold))
                .foregroundStyle(canSend || session.isGenerating ? Color.white : Color.secondary)
                .frame(width: 24, height: 24)
                .background(canSend || session.isGenerating ? Color.accentColor : Color.primary.opacity(0.08),
                            in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!canSend && !session.isGenerating)
        .help(session.isGenerating ? "Stop" : "Send (Return)")
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    private func send() {
        guard !session.isGenerating else { return }
        session.submit(request, model: selectedModel)
        request = ""
    }
}

private struct ActivityPill: View {
    let status: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: status)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 32)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
