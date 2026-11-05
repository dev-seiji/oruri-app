import SwiftUI

struct DictionaryView: View {
    @Environment(AppState.self) private var state
    @LocalState private var showAddWord = false
    @LocalState private var showBulk = false

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(T("Dictionary"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Toggle("", isOn: $state.settings.dictionaryEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.toggleTint)
            }
            .padding(.top, 18)

            Text(T("Names and jargon, spelled your way. Add the correct spelling and close misspellings get fixed; add how a word is misheard if it still slips through. Stored only on this Mac."))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            DictionaryEditor(showAddWord: $showAddWord, showBulk: $showBulk)
                .padding(.top, 16)
                .opacity(state.settings.dictionaryEnabled ? 1 : 0.5)
                .disabled(!state.settings.dictionaryEnabled)

            Spacer()
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 28)
        .sheet(isPresented: $showAddWord) { AddWordSheet() }
        .sheet(isPresented: $showBulk) { BulkImportSheet() }
    }
}

struct DictionaryEditor: View {
    @Environment(AppState.self) private var state
    @Binding var showAddWord: Bool
    @Binding var showBulk: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(state.dictionary) { entry in
                VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(entry.spelling).font(.system(size: 13, weight: .medium))
                    if !entry.heardAs.isEmpty {
                        Text(T("hears it as")).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                        Text(entry.heardAs).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.22)) { state.dictionary.removeAll { $0.id == entry.id } }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help(T("Remove this spelling"))
                }
                Divider()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: 6) {
                SmallBorderedButton(title: "Add word", icon: "plus", dashed: true) { showAddWord = true }
                SmallBorderedButton(title: "Add multiple words", icon: "list.bullet.rectangle") { showBulk = true }
            }
        }
        .animation(.easeOut(duration: 0.22), value: state.dictionary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
    }
}

struct AddWordSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @LocalState private var spelling = ""
    @LocalState private var heard = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(T("Add word")).font(.system(size: 16, weight: .bold))
            VStack(alignment: .leading, spacing: 4) {
                Text(T("Correct spelling")).font(.system(size: 12, weight: .medium))
                TextField(T("e.g. Kubernetes"), text: $spelling).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(T("Oruri hears it as (optional)")).font(.system(size: 12, weight: .medium))
                TextField(T("Optional mishearing"), text: $heard).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button(T("Cancel")) { dismiss() }
                Button(T("Add Word")) {
                    state.dictionary.append(DictionaryEntry(spelling: spelling, heardAs: heard))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(spelling.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct BulkImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @LocalState private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("Add multiple words")).font(.system(size: 16, weight: .bold))
            Text(T("Paste words or phrases, one per line. Two spreadsheet columns also work: correct spelling, then how it's heard."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.cardBorder))
            HStack {
                Spacer()
                Button(T("Cancel")) { dismiss() }
                Button(T("Review corrections")) {
                    for line in text.split(separator: "\n") {
                        let cols = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
                        guard let first = cols.first, !first.isEmpty else { continue }
                        state.dictionary.append(DictionaryEntry(spelling: first, heardAs: cols.count > 1 ? cols[1] : ""))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
