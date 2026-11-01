import AppKit
import InputMethodKit
import AutoTypeCore

/// The per-session input controller.
///
/// macOS creates one of these for every application that talks to the input
/// method, so all mutable state (the word being typed, the marked range, the
/// conversion history) lives here rather than in the shared server.
///
/// The Objective-C name is fixed because the system looks the class up by
/// name through `tsInputMethodPrincipalClass` in the bundle's Info.plist.
@objc(Controller)
final class Controller: IMKInputController {

    // MARK: - State

    /// The Latin text of the word currently being typed.
    private var buffer = ""
    /// The range the marked (composing) text occupies in the client.
    private var markedRange = NSRange(location: NSNotFound, length: 0)
    /// Context for disambiguating the next word.
    private var context = ConversionContext()
    /// The most recent automatic conversion, so it can be undone.
    private var lastConversion: Conversion?
    /// `true` while the user asked AutoType to stand down.
    private(set) var isPaused = false

    // MARK: - Translation State

    private enum TranslationState {
        case idle
        case translating
        case readyToSend(originalText: String, translatedText: String, range: NSRange)
    }

    private var translationState: TranslationState = .idle
    private var sessionLineBuffer = ""

    private struct Conversion {
        let latin: String
        let persian: String
        let range: NSRange
    }

    var loadedEngine: ConversionEngine?
    private var engineLoadError: Error?

    lazy var settingsStore = SettingsStore.shared

    /// Watches the settings folder so a change made in the settings app takes
    /// effect straight away.
    private lazy var settingsWatcher: SettingsWatcher = {
        SettingsWatcher(directory: SettingsStore.applicationSupportDirectory) { [weak self] in
            DispatchQueue.main.async { self?.reloadSettings() }
        }
    }()

    // MARK: - Lifecycle

    override init(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
        _ = settingsWatcher
    }

    override init() {
        super.init()
        _ = settingsWatcher
    }

    // MARK: - Engine

    /// Loads the dictionaries the first time they are needed, so launching the
    /// input method stays instant.
    func makeEngine() -> ConversionEngine {
        if let loadedEngine { return loadedEngine }
        if let engineLoadError { NSLog("AutoType: \(engineLoadError.localizedDescription)") }

        let settings = settingsStore.settings
        do {
            let lexicon = try AutoTypeResources.loadLexicon()
            let dictionary = settingsStore.dictionary
            lexicon.personalPersian = Set(dictionary.persianWords.map(PersianText.lookupKey))
            lexicon.protectedEnglish = Set(dictionary.englishWords.map { $0.lowercased() })
            let created = ConversionEngine(lexicon: lexicon, settings: settings)
            loadedEngine = created
            return created
        } catch {
            engineLoadError = error
            NSLog("AutoType: could not load dictionaries: \(error)")
            let lexicon = try? AutoTypeResources.loadLexicon()
            let created = ConversionEngine(lexicon: lexicon ?? Lexicon.empty(), settings: settings)
            loadedEngine = created
            return created
        }
    }

    /// Re-reads the settings the user changed in the settings app.
    func reloadSettings() {
        let settings = settingsStore.reload()
        let dictionary = settingsStore.reloadDictionary()
        let engine = makeEngine()
        engine.settings = settings
        engine.lexicon.personalPersian = Set(dictionary.persianWords.map(PersianText.lookupKey))
        engine.lexicon.protectedEnglish = Set(dictionary.englishWords.map { $0.lowercased() })
    }

    // MARK: - IMKServerInput

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        guard let client = sender as? IMKTextInput else { return false }
        return handleKeyInput(
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            client: client
        )
    }

    override func activateServer(_ sender: Any!) {
        reloadSettings()
        isPaused = false
        buffer = ""
        markedRange = NSRange(location: NSNotFound, length: 0)
        context = ConversionContext()
        translationState = .idle
        sessionLineBuffer = ""
    }

    override func deactivateServer(_ sender: Any!) {
        flushBuffer(client: sender as? IMKTextInput)
        buffer = ""
        markedRange = NSRange(location: NSNotFound, length: 0)
        translationState = .idle
        sessionLineBuffer = ""
    }

    override func commitComposition(_ sender: Any!) {
        flushBuffer(client: sender as? IMKTextInput)
    }

    override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }
        return handleKeyInput(
            characters: string,
            charactersIgnoringModifiers: string,
            keyCode: UInt16(clamping: keyCode),
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
            client: client
        )
    }

    override func modes(_ sender: Any!) -> [AnyHashable: Any]! {
        let mode = makeEngine().settings.mode
        return ["mode": mode.rawValue]
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        // Ask to receive key events.
        return Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        return nil
    }

    // MARK: - Key handling

    private func logDebug(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/autotype_debug.log")) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/autotype_debug.log"))
            }
        }
    }

    private func handleKeyInput(
        characters: String?,
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        client: IMKTextInput
    ) -> Bool {
        logDebug("handleKeyInput: keyCode=\(keyCode), chars=\(characters ?? ""), flags=\(modifierFlags.rawValue), buf=\(buffer)")

        // Handle readyToSend state for non-Return/non-Escape keys:
        // if user types any character, backspaces, etc., reset translation state so they can edit.
        if case .readyToSend = translationState {
            if keyCode != 36 && keyCode != 76 && keyCode != 53 {
                translationState = .idle
            }
        }

        // Keys the client should handle itself.
        switch keyCode {
        case 123, 124, 125, 126, 115, 116, 119, 121, 117:  // arrows, home, end, page up/down, forward delete
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return false
        case 53:  // Escape
            if handleEscape(client: client) { return true }
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return false
        case 51:  // Delete (backspace)
            return handleBackspace(client: client)
        case 36, 76:  // Return, Keypad Enter
            context = ConversionContext()
            return handleReturn(client: client)
        case 48:  // Tab
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            sessionLineBuffer.append("\t")
            return false
        case 49:  // Space
            if modifierFlags.contains(.shift) {
                // Shift+Space is Persian Zero-Width Non-Joiner (ZWNJ / نیم‌فاصله)
                let currentSettings = makeEngine().settings
                if !currentSettings.isEnabled || currentSettings.mode == .directPersian {
                    client.insertText("\u{200C}", replacementRange: NSRange(location: NSNotFound, length: 0))
                    sessionLineBuffer.append("\u{200C}")
                    return true
                }
                buffer.append("\u{200C}")
                updateMarkedText(client: client)
                return true
            }
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            sessionLineBuffer.append(" ")
            return false
        default:
            break
        }

        // Also handle control characters when keyCode is 0 (e.g. synthesized events or non-standard keyboards)
        if let firstChar = characters?.first, characters?.count == 1 {
            if firstChar == "\u{08}" || firstChar == "\u{7f}" {
                return handleBackspace(client: client)
            }
            if firstChar == "\r" || firstChar == "\n" || firstChar == "\u{03}" {
                return handleReturn(client: client)
            }
            if firstChar == "\u{1b}" {
                if handleEscape(client: client) { return true }
                if !buffer.isEmpty { flushBuffer(client: client) }
                return false
            }
            if firstChar == "\t" {
                if !buffer.isEmpty { flushBuffer(client: client) }
                sessionLineBuffer.append("\t")
                return false
            }
            if firstChar == " " {
                if modifierFlags.contains(.shift) {
                    let currentSettings = makeEngine().settings
                    if !currentSettings.isEnabled || currentSettings.mode == .directPersian {
                        client.insertText("\u{200C}", replacementRange: NSRange(location: NSNotFound, length: 0))
                        sessionLineBuffer.append("\u{200C}")
                        return true
                    }
                    buffer.append("\u{200C}")
                    updateMarkedText(client: client)
                    return true
                }
                if !buffer.isEmpty {
                    flushBuffer(client: client)
                }
                sessionLineBuffer.append(" ")
                return false
            }
        }

        guard !isPaused else { return false }

        let settings = makeEngine().settings
        guard settings.isEnabled else {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            if modifierFlags.contains(.command) || modifierFlags.contains(.control) {
                return false
            }
            if isEnglishModifierActive(modifierFlags) {
                return insertEnglishCharacter(charactersIgnoringModifiers ?? characters, client: client)
            }
            if let characters, characters.count == 1, let ch = characters.first {
                if let ascii = ch.asciiValue, (ascii < 32 || ascii == 127) {
                    return false
                }
                if let letter = PersianLayout.convert(ch) {
                    client.insertText(String(letter), replacementRange: NSRange(location: NSNotFound, length: 0))
                    sessionLineBuffer.append(letter)
                    return true
                }
                sessionLineBuffer.append(ch)
            }
            return false
        }

        // Holding the configured modifier types plain English.
        if isEnglishModifierActive(modifierFlags) {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return insertEnglishCharacter(charactersIgnoringModifiers ?? characters, client: client)
        }

        // Let standard Command or Control shortcuts (Cmd+C, Cmd+V, Cmd+A, Cmd+Z, etc.) pass through.
        if modifierFlags.contains(.command) || modifierFlags.contains(.control) {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return false
        }

        guard let characters, characters.count == 1,
              let character = characters.first else {
            return false
        }

        if let ascii = character.asciiValue, (ascii < 32 || ascii == 127) {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return false
        }

        if settings.mode == .directPersian {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            if let letter = PersianLayout.convert(character) {
                client.insertText(String(letter), replacementRange: NSRange(location: NSNotFound, length: 0))
                sessionLineBuffer.append(letter)
                return true
            }
            return false
        }

        // A word can only end at a word boundary, so a character that can be
        // part of a Persian word keeps the buffer open.
        if isWordCharacter(character) {
            buffer.append(character)
            updateMarkedText(client: client)
            return true
        }

        // Anything else (punctuation, symbols) ends the word and is inserted
        // literally.
        if !buffer.isEmpty {
            flushBuffer(client: client)
        }
        if character == "." || character == "!" || character == "?" || character == "؟" || character == "\n" {
            context = ConversionContext()
        }
        sessionLineBuffer.append(character)
        return false
    }

    /// Backspace removes the last typed character in the buffer, or lets the
    /// client delete normally when the buffer is empty.
    private func handleBackspace(client: IMKTextInput) -> Bool {
        if !buffer.isEmpty {
            buffer.removeLast()
            if buffer.isEmpty {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                markedRange = NSRange(location: NSNotFound, length: 0)
            } else {
                updateMarkedText(client: client)
            }
            return true
        }
        if !sessionLineBuffer.isEmpty {
            sessionLineBuffer.removeLast()
        }
        return false
    }

    /// The raw modifier masks for the right-hand keys. AppKit exposes the
    /// left-hand flags as named constants but not the right-hand ones.
    private enum ModifierMask {
        static let rightCommand = NSEvent.ModifierFlags(rawValue: 1 << 18)
        static let rightOption = NSEvent.ModifierFlags(rawValue: 1 << 19)
        static let rightShift = NSEvent.ModifierFlags(rawValue: 1 << 17)
        static let leftShift = NSEvent.ModifierFlags(rawValue: 1 << 16)
    }

    private func isEnglishModifierActive(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch makeEngine().settings.englishModifier {
        case .none: return false
        case .rightCommand: return flags.contains(ModifierMask.rightCommand)
        case .rightOption: return flags.contains(ModifierMask.rightOption)
        case .rightShift: return flags.contains(ModifierMask.rightShift)
        case .leftShift: return flags.contains(ModifierMask.leftShift)
        }
    }

    private func insertEnglishCharacter(_ characters: String?, client: IMKTextInput) -> Bool {
        guard let characters, characters.count == 1 else { return false }
        client.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    /// Characters that may be part of a word.
    ///
    /// The Persian-only keys (`[ ] ; ' ,`) are included because they carry the
    /// Persian letters `ج چ ک گ و`.
    private func isWordCharacter(_ character: Character) -> Bool {
        if character.isLetter || character.isNumber { return true }
        if PersianLayout.persianOnlyKeys.contains(character) { return true }
        if character == "\u{200C}" { return true }
        return false
    }

    // MARK: - Committing

    private func updateMarkedText(client: IMKTextInput) {
        let displayText: String
        if let persian = PersianLayout.convert(buffer) {
            displayText = persian
        } else {
            displayText = buffer
        }
        let length = (displayText as NSString).length
        client.setMarkedText(
            displayText,
            selectionRange: NSRange(location: length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    /// Decides what the buffered word is and commits it to the client.
    private func flushBuffer(client: IMKTextInput?) {
        guard !buffer.isEmpty else { return }
        let token = buffer
        buffer = ""
        markedRange = NSRange(location: NSNotFound, length: 0)

        guard let client else { return }

        let settings = makeEngine().settings
        let previousWasPersian = context.previousWasPersian
        let decision = makeEngine().decide(token: token, context: context)
        let targetRange = NSRange(location: NSNotFound, length: 0)
        logDebug("flushBuffer: token=\(token), decision=\(decision), mode=\(settings.mode)")

        switch decision {
        case .convertToPersian(let persian):
            var output = persian
            if settings.usePersianDigits {
                output = PersianText.persianDigits(output)
            }
            if settings.usePersianPunctuation {
                output = PersianText.persianPunctuation(output)
            }
            client.insertText(output, replacementRange: targetRange)
            sessionLineBuffer.append(output)
            let locked = context.sentenceLanguageIsPersian ?? true
            context = ConversionContext(
                previousWasPersian: true,
                previousPersianWord: output,
                sentenceLanguageIsPersian: locked
            )
            lastConversion = nil
        case .keepAsTyped(let text):
            var output = text
            if settings.usePersianDigits, previousWasPersian {
                output = PersianText.persianDigits(output)
            }
            if settings.usePersianPunctuation, previousWasPersian {
                output = persianPunctuation(inSuffix: output)
            }
            client.insertText(output, replacementRange: targetRange)
            sessionLineBuffer.append(output)
            let locked = context.sentenceLanguageIsPersian ?? false
            context = ConversionContext(
                previousWasPersian: false,
                previousPersianWord: nil,
                sentenceLanguageIsPersian: locked
            )
            lastConversion = nil
        }
    }

    /// Rewrites the punctuation that trails a word, leaving the word itself
    /// alone.
    private func persianPunctuation(inSuffix text: String) -> String {
        var splitIndex = text.endIndex
        while splitIndex > text.startIndex {
            let previous = text.index(before: splitIndex)
            let character = text[previous]
            if character.isLetter || character.isNumber { break }
            splitIndex = previous
        }
        let word = String(text[..<splitIndex])
        let punctuation = String(text[splitIndex...])
        return word + PersianText.persianPunctuation(punctuation)
    }

    /// Puts the last automatic conversion back to the Latin that produced it.
    private func undoLastConversion(client: IMKTextInput) -> Bool {
        guard let conversion = lastConversion else { return false }
        let caret = client.selectedRange().location
        guard caret == conversion.range.location + conversion.range.length else { return false }
        client.insertText(conversion.latin, replacementRange: conversion.range)
        lastConversion = nil
        context = ConversionContext(previousWasPersian: false, previousPersianWord: nil)
        return true
    }

    // MARK: - Translation on Enter

    private func handleReturn(client: IMKTextInput) -> Bool {
        // Second Enter: user verified the translation and confirms sending.
        if case .readyToSend = translationState {
            translationState = .idle
            sessionLineBuffer = ""
            return false
        }

        // Enter pressed while translation is in flight: ignore to prevent sending untranslated text.
        if case .translating = translationState {
            return true
        }

        if !buffer.isEmpty {
            flushBuffer(client: client)
        }

        let settings = makeEngine().settings
        guard settings.translation.isEnabled,
              !settings.translation.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sessionLineBuffer = ""
            return false
        }

        guard let candidate = extractTextForTranslation(client: client, translationSettings: settings.translation) else {
            logDebug("handleReturn: no candidate for translation (sessionLineBuffer='\(sessionLineBuffer)')")
            sessionLineBuffer = ""
            return false
        }

        let textToTranslate = candidate.text
        let originalLineText = candidate.originalLine
        let rangeToReplace = candidate.range
        logDebug("handleReturn: translating '\(textToTranslate)', range=\(rangeToReplace)")

        translationState = .translating

        Task { @MainActor [weak self, weak client] in
            guard let self = self else { return }
            do {
                let translated = try await TranslationService.shared.translate(
                    text: textToTranslate,
                    settings: settings.translation
                )
                guard case .translating = self.translationState else { return }
                guard let currentClient = client ?? self.client() else {
                    self.translationState = .idle
                    return
                }

                self.logDebug("handleReturn: translation succeeded -> '\(translated)', replacing range=\(rangeToReplace)")
                currentClient.insertText(translated, replacementRange: rangeToReplace)

                let newLength = (translated as NSString).length
                let newLocation: Int
                if rangeToReplace.location != NSNotFound {
                    newLocation = rangeToReplace.location
                } else {
                    let caret = currentClient.selectedRange().location
                    newLocation = caret != NSNotFound ? max(0, caret - newLength) : NSNotFound
                }
                let newRange = NSRange(location: newLocation, length: newLength)

                self.translationState = .readyToSend(
                    originalText: originalLineText,
                    translatedText: translated,
                    range: newRange
                )
                self.sessionLineBuffer = translated
            } catch {
                self.logDebug("handleReturn: translation failed: \(error.localizedDescription)")
                NSLog("AutoType: translation failed: \(error.localizedDescription)")
                self.translationState = .idle
                NSSound.beep()
            }
        }

        // Consume this first Enter so the message is not submitted yet.
        return true
    }

    private func handleEscape(client: IMKTextInput) -> Bool {
        if case .translating = translationState {
            translationState = .idle
            return true
        }
        if case .readyToSend(let originalText, _, let range) = translationState {
            client.insertText(originalText, replacementRange: range)
            translationState = .idle
            sessionLineBuffer = originalText
            return true
        }
        return false
    }

    private func extractTextForTranslation(
        client: IMKTextInput,
        translationSettings: TranslationSettings
    ) -> (text: String, originalLine: String, range: NSRange)? {
        let caret = client.selectedRange().location
        logDebug("extractTextForTranslation: caret=\(caret), sessionLineBuffer='\(sessionLineBuffer)'")
        if caret != NSNotFound && caret > 0 {
            let maxSearch = min(caret, 2000)
            let searchStart = caret - maxSearch
            if let attrString = client.attributedSubstring(from: NSRange(location: searchStart, length: maxSearch)) {
                let fullPrefix = attrString.string
                var lineStartIndex = fullPrefix.startIndex
                if let lastNewline = fullPrefix.rangeOfCharacter(from: .newlines, options: .backwards) {
                    lineStartIndex = lastNewline.upperBound
                }
                let lineSubstring = fullPrefix[lineStartIndex...]
                let lineText = String(lineSubstring).trimmingCharacters(in: .newlines)
                if let translatable = translationSettings.extractTranslatableBody(from: lineText) {
                    let offsetInPrefix = (String(fullPrefix[..<lineStartIndex]) as NSString).length
                    let absoluteLocation = searchStart + offsetInPrefix
                    let length = (String(lineSubstring) as NSString).length
                    return (translatable, lineText, NSRange(location: absoluteLocation, length: length))
                }
            }
        }

        // Fallback to sessionLineBuffer if attributedSubstring is unavailable
        let trimmedBuffer = sessionLineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let translatable = translationSettings.extractTranslatableBody(from: trimmedBuffer) {
            let length = (sessionLineBuffer as NSString).length
            let location = (caret != NSNotFound && caret >= length) ? caret - length : NSNotFound
            return (translatable, trimmedBuffer, NSRange(location: location, length: length))
        }

        return nil
    }

    // MARK: - Explicit commands

    /// Converts the word immediately before the caret.
    @objc func convertWordBeforeCursor(_ sender: Any?) {
        guard let client = client() else { return }
        flushBuffer(client: client)
        let caret = client.selectedRange().location
        guard caret > 0 else { return }

        let searchStart = max(0, caret - 120)
        let prefix = client.attributedSubstring(from: NSRange(location: searchStart, length: caret - searchStart)).string
        guard let wordRange = prefix.range(of: "\\S+$", options: .regularExpression) else { return }
        let word = String(prefix[wordRange])
        let absolute = NSRange(location: searchStart + prefix.distance(from: prefix.startIndex, to: wordRange.lowerBound),
                               length: (word as NSString).length)
        guard let converted = makeEngine().convertWord(before: word), converted != word else { return }
        client.insertText(converted, replacementRange: absolute)
    }

    /// Converts the selected text.
    @objc func convertSelection(_ sender: Any?) {
        guard let client = client() else { return }
        let selection = client.selectedRange()
        guard selection.length > 0 else { return }
        let text = client.attributedSubstring(from: selection).string
        let converted = makeEngine().convertSelection(text)
        guard converted != text else { return }
        client.insertText(converted, replacementRange: selection)
    }

    /// Adds the selected text to the personal dictionary.
    @objc func addSelectionToDictionary(_ sender: Any?) {
        guard let client = client() else { return }
        let selection = client.selectedRange()
        guard selection.length > 0 else { return }
        let text = client.attributedSubstring(from: selection).string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var dictionary = settingsStore.dictionary
        // The two lists are kept apart by the script of the text, not by the
        // punctuation: a Latin word must never end up in the Persian list.
        let isPersian = text.unicodeScalars.contains { PersianLayout.persianLetters.contains(Character($0)) }
        if isPersian {
            let key = PersianText.lookupKey(text)
            if !dictionary.persianWords.contains(key) {
                dictionary.persianWords.append(key)
                dictionary.persianWords.sort()
            }
        } else {
            let key = text.lowercased()
            if !dictionary.englishWords.contains(key) {
                dictionary.englishWords.append(key)
                dictionary.englishWords.sort()
            }
        }
        settingsStore.save(dictionary)
        reloadSettings()
    }

    /// Toggles AutoType on and off.
    @objc func togglePause(_ sender: Any?) {
        isPaused.toggle()
    }

    /// Switches between automatic detection and direct Persian typing.
    @objc func toggleMode(_ sender: Any?) {
        var settings = settingsStore.settings
        settings.mode = settings.mode == .automatic ? .directPersian : .automatic
        settingsStore.save(settings)
        reloadSettings()
    }

    /// Opens the settings app.
    ///
    /// The settings live in their own window, so the app is started with
    /// `--open-settings` and comes up with that window in front of the user.
    @objc func showSettings(_ sender: Any?) {
        let candidates = [
            "/Applications/AutoType Settings.app",
            "\(NSHomeDirectory())/Applications/AutoType Settings.app",
            "\(Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path)/AutoType Settings.app",
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--open-settings"]
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/"))
    }
}
