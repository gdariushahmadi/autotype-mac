import SwiftUI
import AutoTypeCore

struct DictionaryView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var newPersianWord = ""
    @State private var newEnglishWord = ""
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HSplitView {
                wordList(
                    title: "Always Persian",
                    hint: "These words are converted even when they look like English.",
                    words: model.dictionary.persianWords,
                    input: $newPersianWord,
                    placeholder: "Add a Persian word",
                    onAdd: { model.addPersianWord(newPersianWord); newPersianWord = "" },
                    onRemove: model.removePersianWord
                )
                wordList(
                    title: "Always English",
                    hint: "These words are never converted.",
                    words: model.dictionary.englishWords,
                    input: $newEnglishWord,
                    placeholder: "Add an English word",
                    onAdd: { model.addEnglishWord(newEnglishWord); newEnglishWord = "" },
                    onRemove: model.removeEnglishWord
                )
            }
        }
        .onAppear { model.reload() }
    }

    @ViewBuilder
    private func wordList(
        title: String,
        hint: String,
        words: [String],
        input: Binding<String>,
        placeholder: String,
        onAdd: @escaping () -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            List {
                ForEach(filtered(words), id: \.self) { word in
                    HStack {
                        Text(word)
                            .environment(\.layoutDirection, .rightToLeft)
                        Spacer()
                        Button {
                            onRemove(word)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            HStack(spacing: 6) {
                TextField(placeholder, text: input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onAdd)
                Button("Add", action: onAdd)
                    .disabled(input.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(minWidth: 170)
    }

    private func filtered(_ words: [String]) -> [String] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return words }
        return words.filter { $0.lowercased().contains(needle) }
    }
}
