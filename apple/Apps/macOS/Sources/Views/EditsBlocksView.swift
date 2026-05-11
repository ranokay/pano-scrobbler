import Core
import SwiftUI

struct EditsBlocksView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                SimpleEditsPanel(model: model)
                RegexEditsPanel(model: model)
                BlockRulesPanel(model: model)
            }
            .padding(Layout.windowPadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSubtitle("Transform or block scrobbles before they're submitted")
    }
}

// MARK: - Simple Edits

private struct SimpleEditsPanel: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = true
    @State private var matchArtist = ""
    @State private var matchTrack = ""
    @State private var replacementArtist = ""
    @State private var replacementTrack = ""
    @State private var replacementAlbum = ""
    @State private var replacementAlbumArtist = ""

    var body: some View {
        CollapsibleGroupBox(isExpanded: $isExpanded) {
            HStack(spacing: Layout.inlineSpacing) {
                Label("Simple Edits", systemImage: "pencil.line")
                    .font(.headline)
                Spacer()
                Text("\(model.metadataRules.simpleEdits.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    Grid(alignment: .leading, horizontalSpacing: Layout.inlineSpacing, verticalSpacing: Layout.inlineSpacing) {
                        GridRow {
                            TextField("Match artist", text: $matchArtist)
                            TextField("Match track", text: $matchTrack)
                        }
                        GridRow {
                            TextField("New artist", text: $replacementArtist)
                            TextField("New track", text: $replacementTrack)
                        }
                        GridRow {
                            TextField("New album", text: $replacementAlbum)
                            TextField("New album artist", text: $replacementAlbumArtist)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button {
                            addEdit()
                        } label: {
                            Label("Add Edit", systemImage: "plus")
                        }
                        .disabled(
                            matchArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || matchTrack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    if !model.metadataRules.simpleEdits.isEmpty {
                        Divider()

                        VStack(spacing: 0) {
                            ForEach(Array(model.metadataRules.simpleEdits.enumerated()), id: \.element.id) { index, edit in
                                editRow(edit: edit, index: index)
                                if index < model.metadataRules.simpleEdits.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
    }

    private func editRow(edit: SimpleEdit, index: Int) -> some View {
        HStack(spacing: Layout.inlineSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(edit.matchArtist) — \(edit.matchTrack)")
                    .font(.callout.weight(.medium))
                Text(summary(edit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                withAnimation {
                    model.removeSimpleEdits(at: IndexSet(integer: index))
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private func addEdit() {
        model.addSimpleEdit(
            matchArtist: matchArtist,
            matchTrack: matchTrack,
            replacementArtist: replacementArtist,
            replacementTrack: replacementTrack,
            replacementAlbum: replacementAlbum,
            replacementAlbumArtist: replacementAlbumArtist
        )
        matchArtist = ""
        matchTrack = ""
        replacementArtist = ""
        replacementTrack = ""
        replacementAlbum = ""
        replacementAlbumArtist = ""
    }

    private func summary(_ edit: SimpleEdit) -> String {
        [
            edit.replacementArtist.map { "artist → \($0)" },
            edit.replacementTrack.map { "track → \($0)" },
            edit.replacementAlbum.map { "album → \($0)" },
            edit.replacementAlbumArtist.map { "album artist → \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

// MARK: - Regex Edits

private struct RegexEditsPanel: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = false
    @State private var field: RegexEdit.Field = .track
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var testInput = ""
    @State private var showTest = false

    var body: some View {
        CollapsibleGroupBox(isExpanded: $isExpanded) {
            HStack(spacing: Layout.inlineSpacing) {
                Label("Regex Edits", systemImage: "textformat.abc")
                    .font(.headline)
                Spacer()
                Text("\(model.metadataRules.regexEdits.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                HStack(spacing: Layout.inlineSpacing) {
                    Picker("Field", selection: $field) {
                        ForEach(RegexEdit.Field.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    TextField("Pattern", text: $pattern)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    TextField("Replacement", text: $replacement)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        model.addRegexEdit(field: field, pattern: pattern, replacement: replacement)
                        pattern = ""
                        replacement = ""
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                DisclosureGroup(isExpanded: $showTest) {
                    VStack(alignment: .leading, spacing: Layout.inlineSpacing) {
                        TextField("Enter test text…", text: $testInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())

                        if !testInput.isEmpty {
                            regexTestResults
                        }
                    }
                    .padding(.top, Layout.inlineSpacing)
                } label: {
                    Label("Test Regex", systemImage: "flask")
                        .font(.callout)
                }

                if !model.metadataRules.regexEdits.isEmpty {
                    Divider()

                    VStack(spacing: 0) {
                        ForEach(Array(model.metadataRules.regexEdits.enumerated()), id: \.element.id) { index, edit in
                            regexRow(edit: edit, index: index)
                            if index < model.metadataRules.regexEdits.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func regexRow(edit: RegexEdit, index: Int) -> some View {
        HStack(spacing: Layout.inlineSpacing) {
            Text(edit.field.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.tint.opacity(0.15), in: Capsule())
                .foregroundStyle(.tint)

            Text(edit.pattern)
                .font(.callout.monospaced())
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Text(edit.replacement)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                withAnimation {
                    model.removeRegexEdits(at: IndexSet(integer: index))
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var regexTestResults: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.metadataRules.regexEdits) { edit in
                let result = testRegex(pattern: edit.pattern, replacement: edit.replacement, input: testInput)
                HStack(spacing: Layout.inlineSpacing) {
                    Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.matches ? .green : .secondary)
                        .font(.caption)

                    Text(edit.pattern)
                        .font(.caption.monospaced())
                        .foregroundStyle(result.matches ? .primary : .secondary)
                        .lineLimit(1)

                    if result.matches {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                        Text(result.output)
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }
            }

            if model.metadataRules.regexEdits.isEmpty {
                Text("No regex edits to test.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !pattern.isEmpty {
                Divider()
                let result = testRegex(pattern: pattern, replacement: replacement, input: testInput)
                HStack(spacing: Layout.inlineSpacing) {
                    Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.matches ? .green : .secondary)
                        .font(.caption)

                    Text(pattern)
                        .font(.caption.monospaced())
                        .foregroundStyle(result.matches ? .primary : .secondary)

                    Text("(unsaved)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if result.matches {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption2)
                        Text(result.output)
                            .font(.caption.monospaced())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private func testRegex(pattern: String, replacement: String, input: String) -> (matches: Bool, output: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (false, input)
        }
        let range = NSRange(input.startIndex..., in: input)
        let matches = regex.firstMatch(in: input, range: range) != nil
        let output = regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
        return (matches, output)
    }
}

// MARK: - Block Rules

private struct BlockRulesPanel: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = false
    @State private var blockField: BlockRule.Field = .artist
    @State private var blockValue = ""

    var body: some View {
        CollapsibleGroupBox(isExpanded: $isExpanded) {
            HStack(spacing: Layout.inlineSpacing) {
                Label("Block Rules", systemImage: "hand.raised.fill")
                    .font(.headline)
                Spacer()
                Text("\(model.metadataRules.blockRules.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } content: {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                HStack(spacing: Layout.inlineSpacing) {
                    Picker("Field", selection: $blockField) {
                        ForEach(BlockRule.Field.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    TextField("Exact value to block", text: $blockValue)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addBlock() }

                    Button {
                        addBlock()
                    } label: {
                        Label("Block", systemImage: "nosign")
                    }
                    .disabled(blockValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !model.metadataRules.blockRules.isEmpty {
                    Divider()

                    VStack(spacing: 0) {
                        ForEach(Array(model.metadataRules.blockRules.enumerated()), id: \.element.id) { index, rule in
                            blockRow(rule: rule, index: index)
                            if index < model.metadataRules.blockRules.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func blockRow(rule: BlockRule, index: Int) -> some View {
        HStack(spacing: Layout.inlineSpacing) {
            Text(rule.field.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)

            Text(rule.value)
                .font(.callout.weight(.medium))

            Spacer()

            Text(rule.action.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                withAnimation {
                    model.removeBlockRules(at: IndexSet(integer: index))
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private func addBlock() {
        model.addBlockRule(field: blockField, value: blockValue)
        blockValue = ""
    }
}
