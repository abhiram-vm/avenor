import SwiftUI

// MARK: - NoteRow (Sophisticated Stark)
//
// Minimalist note row: neutral charcoal rail (0.35 opacity), meta-strip with word count
// and edit timestamp, title field, expand for full text editor.

struct NoteRow: View {
    @Environment(ThemeStore.self) private var theme
    @Bindable var note: PersistedNote
    var isExpanded: Bool
    var onToggleExpanded: () -> Void
    var onDelete: () -> Void

    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool

    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle()
                .fill(p.textTertiary)
                .frame(width: 2)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                metaStrip
                titleRow

                if !note.details.isEmpty && !isExpanded {
                    // Collapsed preview — render markdown so inline bold /
                    // italic / bullets read correctly in the row.
                    Text(MarkdownRenderer.render(note.details))
                        .font(p.font(.body))
                        .foregroundStyle(p.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                }

                if isExpanded {
                    editorBlock
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(p.rowFill)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // `.task` fires after the first render, which is when the field is
        // attachable — focusing a brand-new empty row without a timing hack.
        .task {
            if note.title.isEmpty { isTitleFocused = true }
        }
    }

    // MARK: Meta strip — NOTE · [WORD COUNT] · EDITED [DATE]

    private var metaStrip: some View {
        HStack(spacing: 0) {
            metaToken("Note")

            separator

            metaToken("\(note.wordCount) words", monospaced: true)

            separator

            if let edited = note.lastEditedAt {
                metaToken("Edited \(TaskDateFormatter.friendlyDue(edited))")
            } else {
                metaToken("New")
            }

            Spacer(minLength: 0)
        }
    }

    private func metaToken(_ text: String, monospaced: Bool = false) -> some View {
        let p = theme.palette
        return Text(text)
            .font(p.font(.micro))
            .tracking(p.microTracking)
            .textCase(.uppercase)
            .conditionalMonospaced(monospaced)
            .foregroundStyle(p.textSecondary)
            .lineLimit(1)
    }

    private var separator: some View {
        let p = theme.palette
        return Text("·")
            .font(p.font(.micro))
            .foregroundStyle(p.textTertiary)
            .padding(.horizontal, 8)
    }

    // MARK: Title row

    private var titleRow: some View {
        let p = theme.palette
        return HStack(alignment: .center, spacing: 12) {
            TextField("Note title…", text: $note.title)
                .focused($isTitleFocused)
                .font(p.font(.headline))
                .tracking(p.headlineTracking)
                .foregroundStyle(p.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .onChange(of: note.title) { _, _ in
                    note.lastEditedAt = .now
                }

            Spacer(minLength: 0)

            Button { onToggleExpanded() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(p.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Editor block
    //
    // Read state by default: tap-to-edit reveals the underlying TextEditor.
    // The rendered AttributedString preserves inline **bold**, *italic*,
    // `code`, and promoted `• item` bullets with editorial line spacing.
    // The editor itself stays raw markdown — what you type is what saves.

    private var editorBlock: some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(isBodyFocused ? "Editing" : "Body")
                    .font(p.font(.micro))
                    .tracking(p.microTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(p.textSecondary)

                Spacer(minLength: 0)

                if isBodyFocused {
                    Button("Done") { isBodyFocused = false }
                        .font(p.font(.micro))
                        .tracking(p.microTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(p.textPrimary)
                        .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                if isBodyFocused || note.details.isEmpty {
                    editor
                } else {
                    rendered
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(p.chromeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(
                        isBodyFocused ? p.prominent : p.hairline,
                        lineWidth: 0.5
                    )
            )
        }
        .padding(.top, 4)
        .animation(DesignTokens.Motion.snappy, value: isBodyFocused)
    }

    // MARK: Rendered read state

    private var rendered: some View {
        let p = theme.palette
        return Text(MarkdownRenderer.render(note.details))
            .font(p.font(.body))
            .foregroundStyle(p.textPrimary)
            .lineSpacing(5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                isBodyFocused = true
            }
    }

    // MARK: Raw editor

    private var editor: some View {
        let p = theme.palette
        return ZStack(alignment: .topLeading) {
            if note.details.isEmpty {
                Text("Write your note…  **bold**, *italic*, - bullet")
                    .font(p.font(.body))
                    .foregroundStyle(p.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $note.details)
                .focused($isBodyFocused)
                .scrollContentBackground(.hidden)
                .font(p.font(.body))
                .foregroundStyle(p.textPrimary)
                .lineSpacing(5)
                .frame(minHeight: 140)
                .onChange(of: note.details) { _, _ in
                    note.lastEditedAt = .now
                }
        }
    }
}

// MARK: - Helper extension for conditional monospaced

extension View {
    func conditionalMonospaced(_ apply: Bool) -> some View {
        if apply {
            return AnyView(self.monospacedDigit())
        } else {
            return AnyView(self)
        }
    }
}
