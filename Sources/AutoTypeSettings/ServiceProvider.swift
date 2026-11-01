import AppKit
import AutoTypeCore

/// The AutoType actions that macOS offers as *Services*.
///
/// A service is declared in the app bundle's `Info.plist` under `NSServices`
/// and macOS then calls the provider through a method that is named after the
/// service message: `<NSMessage>:userData:error:`. The selected text arrives
/// on the pasteboard; the answer is written back onto the same pasteboard and
/// the app that started the service replaces its selection with it.
///
/// The messages therefore have to stay in step with the `NSMessage` values
/// in `Scripts/package_app.sh`.
final class ServiceProvider: NSObject {

    // MARK: - Registration

    /// The one provider the app uses, so the object AppKit holds never goes
    /// away.
    static let shared = ServiceProvider()

    /// Hands the provider to AppKit.
    ///
    /// The provider has to be in place before the first service request can
    /// arrive, so this is called as early as the app allows. The application
    /// is passed in because a SwiftUI app does not use the shared
    /// `NSApplication` instance, and `NSApp` stays empty.
    static func register(in application: NSApplication?) {
        guard let application else {
            NSLog("AutoType: the service provider could not be registered")
            return
        }
        application.servicesProvider = ServiceProvider.shared
    }

    // MARK: - Engine

    /// The engine is built once and then kept: loading the dictionaries takes
    /// a moment and the service can be called at any time.
    private static var sharedEngine: ConversionEngine?

    private func engine() -> ConversionEngine? {
        if let engine = ServiceProvider.sharedEngine { return engine }

        let store = SettingsStore.shared
        do {
            let lexicon = try AutoTypeResources.loadLexicon()
            let created = ConversionEngine(lexicon: lexicon, settings: store.reload())
            ServiceProvider.sharedEngine = created
            return created
        } catch {
            NSLog("AutoType: the service could not load the dictionaries: \(error.localizedDescription)")
            return nil
        }
    }

    /// The personal dictionary may have changed since the engine was built.
    private func refreshDictionary() {
        guard let engine = engine() else { return }
        let dictionary = SettingsStore.shared.reloadDictionary()
        engine.lexicon.personalPersian = Set(dictionary.persianWords.map(PersianText.lookupKey))
        engine.lexicon.protectedEnglish = Set(dictionary.englishWords.map { $0.lowercased() })
    }

    // MARK: - The services

    /// Turns the selected Latin words into Persian.
    @objc func convertSelectionToPersian(
        _ pasteboard: NSPasteboard,
        userData: [AnyHashable: Any],
        error: NSErrorPointer
    ) -> Bool {
        NSLog("AutoType: the service Convert to Persian was called")
        guard let text = selectedText(in: pasteboard) else {
            NSLog("AutoType: the service found no text on the pasteboard")
            return false
        }
        guard let engine = engine() else { return false }
        refreshDictionary()
        return write(engine.convertText(text), to: pasteboard)
    }

    /// Translates the selected text with the configured AI provider.
    @objc func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: [AnyHashable: Any],
        error: NSErrorPointer
    ) -> Bool {
        NSLog("AutoType: the service Translate with AI was called")
        guard let text = selectedText(in: pasteboard) else {
            NSLog("AutoType: the service found no text on the pasteboard")
            return false
        }

        var translation = SettingsStore.shared.reload().translation
        guard !translation.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentMissingAPIKey()
            return false
        }
        // The configured prompt translates Persian into English, so English
        // text needs the other direction.
        if !PersianText.containsPersian(text) {
            translation.systemPrompt = "You are a professional translator. Translate the given English text into fluent, natural Persian. Output ONLY the translated text without explanations, quotes, or notes."
        }

        guard let translated = translateSynchronously(text, settings: translation) else {
            presentTranslationFailure()
            return false
        }
        return write(translated, to: pasteboard)
    }

    /// Adds the selected word to the personal dictionary.
    @objc func addSelectionToDictionary(
        _ pasteboard: NSPasteboard,
        userData: [AnyHashable: Any],
        error: NSErrorPointer
    ) -> Bool {
        NSLog("AutoType: the service Add to Dictionary was called")
        guard let text = selectedText(in: pasteboard) else {
            NSLog("AutoType: the service found no text on the pasteboard")
            return false
        }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return false }

        var dictionary = SettingsStore.shared.reloadDictionary()
        // The two lists are kept apart by the script of the text, not by the
        // punctuation: a Latin word must never end up in the Persian list.
        let isPersian = word.unicodeScalars.contains { PersianLayout.persianLetters.contains(Character($0)) }
        if isPersian {
            let key = PersianText.lookupKey(word)
            if !dictionary.persianWords.contains(key) {
                dictionary.persianWords.append(key)
                dictionary.persianWords.sort()
            }
        } else {
            let key = word.lowercased()
            if !dictionary.englishWords.contains(key) {
                dictionary.englishWords.append(key)
                dictionary.englishWords.sort()
            }
        }
        SettingsStore.shared.save(dictionary)

        // The selection itself does not change.
        return true
    }

    /// Turns the selected Persian text into the Latin keys that produce it.
    @objc func convertSelectionToLatin(
        _ pasteboard: NSPasteboard,
        userData: [AnyHashable: Any],
        error: NSErrorPointer
    ) -> Bool {
        NSLog("AutoType: the service Convert to Latin was called")
        guard let text = selectedText(in: pasteboard) else {
            NSLog("AutoType: the service found no text on the pasteboard")
            return false
        }
        return write(PersianLayout.latinize(text), to: pasteboard)
    }

    // MARK: - Pasteboard

    /// The text the user had selected when the service was started.
    private func selectedText(in pasteboard: NSPasteboard) -> String? {
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return text }
        if let text = pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")), !text.isEmpty { return text }
        if let attributed = pasteboard.readObjects(
            forClasses: [NSAttributedString.self],
            options: nil
        ) as? [NSAttributedString], let text = attributed.first?.string, !text.isEmpty {
            return text
        }
        return nil
    }

    /// Puts the answer on the pasteboard, where the app that started the
    /// service will pick it up.
    private func write(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return true
    }

    // MARK: - Translation

    /// Runs the translation and waits for it.
    ///
    /// The service has to answer before macOS reads the pasteboard, so the
    /// request is made off the main actor and the call waits for it.
    private func translateSynchronously(_ text: String, settings: TranslationSettings) -> String? {
        let outcome = TranslationOutcome()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            do {
                let translated = try await TranslationService.shared.translate(text: text, settings: settings)
                outcome.set(.success(translated))
            } catch {
                outcome.set(.failure(error))
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 30) == .success else {
            NSLog("AutoType: the translation service timed out")
            return nil
        }

        switch outcome.value {
        case .success(let translated):
            return translated
        case .failure(let error):
            NSLog("AutoType: the translation failed: \(error.localizedDescription)")
            return nil
        case .none:
            return nil
        }
    }

    // MARK: - Messages

    private func presentMissingAPIKey() {
        NSLog("AutoType: the translation service needs an API key")
        let alert = NSAlert()
        alert.messageText = "AutoType has no translation key yet"
        alert.informativeText = "Add your API key in AutoType Settings, then try the Translate service again."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentTranslationFailure() {
        let alert = NSAlert()
        alert.messageText = "The translation failed"
        alert.informativeText = "AutoType could not reach the translation service. Check the API key and the endpoint in AutoType Settings."
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Carries the result of the translation from the background task back to the
/// service call.
private final class TranslationOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<String, Error>?

    var value: Result<String, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: Result<String, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}
