import Core
import SwiftUI

struct EditsBlocksView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Edits & Blocks")
                        .font(.displayLarge)
                    Text("Transform or block scrobbles before they're submitted.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: Spacing.md) {
                    PipelineBadge(icon: "pencil.line", label: "Simple", count: model.metadataRules.simpleEdits.count, color: AccentColors.primary)
                    PipelineBadge(icon: "textformat.abc", label: "Regex", count: model.metadataRules.regexEdits.count, color: AccentColors.secondary)
                    PipelineBadge(icon: "hand.raised.fill", label: "Blocks", count: model.metadataRules.blockRules.count, color: AccentColors.error)
                }

                SimpleEditsPanel(model: model)
                RegexEditsPanel(model: model)
                BlockRulesPanel(model: model)
            }
            .padding(Spacing.lg)
        }
    }
}

private struct PipelineBadge: View {
    var icon: String; var label: String; var count: Int; var color: Color
    var body: some View {
        GlassCard(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.metricLabel).foregroundStyle(.secondary).textCase(.uppercase)
                    Text("\(count)").font(.metricValue).contentTransition(.numericText())
                }
            }
        }
    }
}

private struct SimpleEditsPanel: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = true
    @State private var matchArtist = ""; @State private var matchTrack = ""
    @State private var replacementArtist = ""; @State private var replacementTrack = ""
    @State private var replacementAlbum = ""; @State private var replacementAlbumArtist = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
                            GridRow { TextField("Match artist", text: $matchArtist); TextField("Match track", text: $matchTrack) }
                            GridRow { TextField("New artist", text: $replacementArtist); TextField("New track", text: $replacementTrack) }
                            GridRow { TextField("New album", text: $replacementAlbum); TextField("New album artist", text: $replacementAlbumArtist) }
                        }.textFieldStyle(.roundedBorder)
                        HStack {
                            Spacer()
                            Button { addEdit() } label: { Label("Add Edit", systemImage: "plus") }
                                
                                .disabled(matchArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || matchTrack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                ForEach(Array(model.metadataRules.simpleEdits.enumerated()), id: \.element.id) { index, edit in
                    GlassCard(spacing: Spacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(edit.matchArtist) — \(edit.matchTrack)").font(.system(size: 13, weight: .semibold))
                                Text(summary(edit)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { withAnimation(.spring(duration: 0.3)) { model.removeSimpleEdits(at: IndexSet(integer: index)) } } label: { Image(systemName: "trash").font(.system(size: 11)) }.buttonStyle(.borderless)
                        }
                    }
                }
            }.padding(.top, Spacing.sm)
        } label: {
            Label { HStack { Text("Simple Edits").font(.displaySmall); Spacer(); StatusBadge(count: model.metadataRules.simpleEdits.count, color: AccentColors.primary) } } icon: { Image(systemName: "pencil.line").foregroundStyle(AccentColors.primary) }
        }
    }

    private func addEdit() {
        model.addSimpleEdit(matchArtist: matchArtist, matchTrack: matchTrack, replacementArtist: replacementArtist, replacementTrack: replacementTrack, replacementAlbum: replacementAlbum, replacementAlbumArtist: replacementAlbumArtist)
        matchArtist = ""; matchTrack = ""; replacementArtist = ""; replacementTrack = ""; replacementAlbum = ""; replacementAlbumArtist = ""
    }

    private func summary(_ edit: SimpleEdit) -> String {
        [edit.replacementArtist.map { "artist → \($0)" }, edit.replacementTrack.map { "track → \($0)" }, edit.replacementAlbum.map { "album → \($0)" }, edit.replacementAlbumArtist.map { "album artist → \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct RegexEditsPanel: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = false
    @State private var field: RegexEdit.Field = .track
    @State private var pattern = ""; @State private var replacement = ""
    @State private var testInput = ""
    @State private var showTest = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                GlassCard {
                    HStack(spacing: Spacing.sm) {
                        Picker("Field", selection: $field) { ForEach(RegexEdit.Field.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 140)
                        TextField("Pattern", text: $pattern).textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary).font(.system(size: 11))
                        TextField("Replacement", text: $replacement).textFieldStyle(.roundedBorder)
                        Button { model.addRegexEdit(field: field, pattern: pattern, replacement: replacement); pattern = ""; replacement = "" } label: { Label("Add", systemImage: "plus") }.disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                // Regex test area
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showTest.toggle() }
                            } label: {
                                Label("Test Regex", systemImage: showTest ? "flask.fill" : "flask")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }

                        if showTest {
                            TextField("Enter test text…", text: $testInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, design: .monospaced))

                            if !testInput.isEmpty {
                                regexTestResults
                            }
                        }
                    }
                }

                ForEach(Array(model.metadataRules.regexEdits.enumerated()), id: \.element.id) { index, edit in
                    GlassCard(spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Text(edit.field.rawValue).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(AccentColors.secondary).padding(.horizontal, 8).padding(.vertical, 3).background(AccentColors.secondary.opacity(0.12), in: Capsule())
                            Text(edit.pattern).font(.system(size: 12, design: .monospaced))
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary).font(.system(size: 10))
                            Text(edit.replacement).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) { withAnimation(.spring(duration: 0.3)) { model.removeRegexEdits(at: IndexSet(integer: index)) } } label: { Image(systemName: "trash").font(.system(size: 11)) }.buttonStyle(.borderless)
                        }
                    }
                }
            }.padding(.top, Spacing.sm)
        } label: {
            Label { HStack { Text("Regex Edits").font(.displaySmall); Spacer(); StatusBadge(count: model.metadataRules.regexEdits.count, color: AccentColors.secondary) } } icon: { Image(systemName: "textformat.abc").foregroundStyle(AccentColors.secondary) }
        }
    }

    @ViewBuilder
    private var regexTestResults: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(model.metadataRules.regexEdits) { edit in
                let result = testRegex(pattern: edit.pattern, replacement: edit.replacement, input: testInput)
                HStack(spacing: Spacing.sm) {
                    Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(result.matches ? AccentColors.success : .secondary.opacity(0.5))

                    Text(edit.pattern)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(result.matches ? .primary : .secondary)
                        .lineLimit(1)

                    if result.matches {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)

                        Text(result.output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AccentColors.success)
                            .lineLimit(1)
                    }
                }
            }

            if model.metadataRules.regexEdits.isEmpty {
                Text("No regex edits to test.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Also test the current unsaved pattern
            if !pattern.isEmpty {
                Divider()
                let result = testRegex(pattern: pattern, replacement: replacement, input: testInput)
                HStack(spacing: Spacing.sm) {
                    Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(result.matches ? AccentColors.success : .secondary.opacity(0.5))

                    Text(pattern)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(result.matches ? .primary : .secondary)

                    Text("(unsaved)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if result.matches {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)

                        Text(result.output)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AccentColors.success)
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

private struct BlockRulesPanel: View {
    @ObservedObject var model: AppModel
    @State private var isExpanded = false
    @State private var blockField: BlockRule.Field = .artist
    @State private var blockValue = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                GlassCard {
                    HStack(spacing: Spacing.sm) {
                        Picker("Field", selection: $blockField) { ForEach(BlockRule.Field.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 140)
                        TextField("Exact value to block", text: $blockValue).textFieldStyle(.roundedBorder).onSubmit { addBlock() }
                        Button { addBlock() } label: { Label("Block", systemImage: "nosign") }.disabled(blockValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                ForEach(Array(model.metadataRules.blockRules.enumerated()), id: \.element.id) { index, rule in
                    GlassCard(spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Text(rule.field.rawValue).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(AccentColors.error).padding(.horizontal, 8).padding(.vertical, 3).background(AccentColors.error.opacity(0.12), in: Capsule())
                            Text(rule.value).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(rule.action.rawValue).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                            Button(role: .destructive) { withAnimation(.spring(duration: 0.3)) { model.removeBlockRules(at: IndexSet(integer: index)) } } label: { Image(systemName: "trash").font(.system(size: 11)) }.buttonStyle(.borderless)
                        }
                    }
                }
            }.padding(.top, Spacing.sm)
        } label: {
            Label { HStack { Text("Block Rules").font(.displaySmall); Spacer(); StatusBadge(count: model.metadataRules.blockRules.count, color: AccentColors.error) } } icon: { Image(systemName: "hand.raised.fill").foregroundStyle(AccentColors.error) }
        }
    }

    private func addBlock() { model.addBlockRule(field: blockField, value: blockValue); blockValue = "" }
}
