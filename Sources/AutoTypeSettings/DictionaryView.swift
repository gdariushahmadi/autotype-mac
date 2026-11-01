import SwiftUI
import AutoTypeCore

/// The personal dictionary: words that always convert, and words that never do.
///
/// The two lists sit behind a segmented control rather than side by side, so
/// the pane stays as calm as the rest of the window.
struct DictionarySettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var newWord = ""
    @State private var search = ""
    @State private var list: WordList = .persian

    /// The two lists of the dictionary.
    enum WordList: String, CaseIterable, Identifiable {
        case persian
        case english

        var id: String { rawValue }

        var title: String {
            switch self {
            case .persian: return "Always Persian"
            case .english: return "Always English"
            }
        }

        var symbol: String {
            switch self {
            case .persian: return "character.book.closed"
            case .english: return "character.bubble"
            }
        }

        var hint: String {
            switch self {
            case .persian: return "These words are converted even when they look like English."
            case .english: return "These words are never converted."
            }
        }

        var placeholder: String {
            switch self {
            case .persian: return "Add a Persian word"
            case .english: return "Add an English word"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, placeholder: "Search words")
                .padding(.horizontal, AutoTypeMetrics.gutter)
                .padding(.top, 12)
                .padding(.bottom, 10)

            // The filter sits at the left of the pane, with everything else
            // that is in it.
            HStack(spacing: 0) {
                Picker("", selection: $list) {
                    ForEach(WordList.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Dictionary list")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AutoTypeMetrics.gutter)
            .padding(.bottom, 10)

            header

            content

            addRow
        }
        .onAppear { model.reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // No `fixedSize` here: this pane is not in a form, so a text that
            // asks for its own height would make the window grow past its
            // size.
            Text(list.hint)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            CountBadge(count: words.count)
        }
        .padding(.horizontal, AutoTypeMetrics.gutter)
        .padding(.bottom, 8)
    }

    // MARK: - The list

    @ViewBuilder
    private var content: some View {
        if visible.isEmpty {
            // The message sits in the middle of the room that is left, and the
            // field at the bottom of the pane stays at the bottom.
            Spacer(minLength: 0)
            emptyState
            Spacer(minLength: 0)
        } else {
            List {
                ForEach(visible, id: \.self) { word in
                    HStack(spacing: 8) {
                        Text(word)
                            .environment(\.layoutDirection, .rightToLeft)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            remove(word)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove this word")
                    }
                    .padding(.vertical, 1)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
        }
    }

    /// What the pane shows when there is nothing to list.
    ///
    /// It is built by hand rather than with `ContentUnavailableView`, because
    /// that one asks for far more height than the pane has, and the window
    /// then grows past the size it was given.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: list.symbol)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)

            Text(search.isEmpty ? "No words yet" : "No matches")
                .font(.headline)

            Text(search.isEmpty
                 ? "Add a word below and AutoType always converts it."
                 : "No word contains “\(search)”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Adding a word

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField(list.placeholder, text: $newWord)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit(addWord)
            Button("Add", action: addWord)
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AutoTypeMetrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - The words themselves

    private var words: [String] {
        switch list {
        case .persian: return model.dictionary.persianWords
        case .english: return model.dictionary.englishWords
        }
    }

    private var visible: [String] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return words }
        return words.filter { $0.lowercased().contains(needle) }
    }

    // MARK: - Editing

    private func addWord() {
        switch list {
        case .persian:
            model.addPersianWord(newWord)
        case .english:
            model.addEnglishWord(newWord)
        }
        newWord = ""
    }

    private func remove(_ word: String) {
        switch list {
        case .persian:
            model.removePersianWord(word)
        case .english:
            model.removeEnglishWord(word)
        }
    }
}
