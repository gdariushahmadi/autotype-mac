import Foundation
import Testing
@testable import AutoTypeCore

@Suite("Settings key storage")
struct CredentialStoreTests {
    @Test("Save, reload and remove the key in the settings file")
    func saveAndRemoveKey() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("settings.json")
        let dictionary = folder.appendingPathComponent("dictionary.json")
        let store = SettingsStore(settingsURL: url, dictionaryURL: dictionary)
        var settings = store.settings
        settings.translation.apiKey = "test-key"
        #expect(store.save(settings))
        #expect(store.reload().translation.apiKey == "test-key")
        let stored = try JSONDecoder().decode(ConversionSettings.self, from: Data(contentsOf: url))
        #expect(stored.translation.apiKey == "test-key")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        settings.translation.apiKey = ""
        #expect(store.save(settings))
        let reopened = SettingsStore(settingsURL: url, dictionaryURL: dictionary)
        #expect(reopened.settings.translation.apiKey.isEmpty)
    }
}
