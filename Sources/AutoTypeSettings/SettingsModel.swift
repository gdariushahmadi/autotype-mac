import Foundation
import SwiftUI
import AutoTypeCore

/// The settings window's state.
///
/// The input method and this app are separate processes, so every change is
/// written straight to disk through `SettingsStore`; the input method watches
/// the same file and picks the change up.
final class SettingsModel: ObservableObject {

    @Published var settings: ConversionSettings {
        didSet { store.save(settings) }
    }

    @Published var dictionary: PersonalDictionary {
        didSet { store.save(dictionary) }
    }

    @Published var inputSourceStatus: InputSourceStatus = .unknown

    private let store = SettingsStore.shared

    init() {
        settings = store.settings
        dictionary = store.dictionary
        refreshInputSourceStatus()
    }

    /// Re-reads the files, in case the input method or another window changed
    /// them.
    func reload() {
        let newSettings = store.reload()
        let newDictionary = store.reloadDictionary()
        if newSettings != settings { settings = newSettings }
        if newDictionary != dictionary { dictionary = newDictionary }
    }

    func refreshInputSourceStatus() {
        inputSourceStatus = InputSourceStatus.current()
    }

    // MARK: - Personal dictionary

    /// Adds a word to the Persian list.
    func addPersianWord(_ word: String) {
        let key = PersianText.lookupKey(word.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty, !dictionary.persianWords.contains(key) else { return }
        dictionary.persianWords.append(key)
        dictionary.persianWords.sort()
    }

    /// Adds a word to the English list.
    func addEnglishWord(_ word: String) {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !dictionary.englishWords.contains(key) else { return }
        dictionary.englishWords.append(key)
        dictionary.englishWords.sort()
    }

    func removePersianWord(_ word: String) {
        dictionary.persianWords.removeAll { $0 == word }
    }

    func removeEnglishWord(_ word: String) {
        dictionary.englishWords.removeAll { $0 == word }
    }

    /// Adds a word or phrase to the forbidden list.
    func addForbiddenWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !dictionary.forbiddenWords.contains(trimmed) else { return }
        dictionary.forbiddenWords.append(trimmed)
        dictionary.forbiddenWords.sort()
    }

    func removeForbiddenWord(_ word: String) {
        dictionary.forbiddenWords.removeAll { $0 == word }
    }
}
