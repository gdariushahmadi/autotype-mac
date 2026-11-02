import AppKit
import CoreGraphics
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
    private static var englishOnly = false
    private static var englishStatusItem: NSStatusItem?
    private var shiftDown: UInt16?
    private var shiftTapWasUsed = false
    private var lastShiftTap: (key: UInt16, time: TimeInterval)?
    private var shiftPollTimer: Timer?
    private var observedShift = false
    var observedCapsLock = false

    var isEnglishOnly: Bool { Self.englishOnly }
    /// The most recent automatic conversion, so it can be undone.
    private var lastConversion: Conversion?
    /// `true` while the user asked AutoType to stand down.
    private(set) var isPaused = false

    // MARK: - Translation State

    private enum TranslationState {
        case idle
        case translating(id: UUID)
        case readyToSend(originalText: String, translatedText: String, range: NSRange)
    }

    private var translationState: TranslationState = .idle
    private var translationTask: Task<Void, Never>?
    var translationProcessor: (String, String, TranslationSettings) async throws -> String = { text, prompt, settings in
        try await TranslationService.shared.process(text: text, systemPrompt: prompt, settings: settings)
    }
    private var awaitingForbiddenConfirmation: (detectedWords: [String], line: String)? = nil
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
        if settings.englishModifier == .capsLock {
            let isCapsOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
            syncCapsLockState(isCapsOn)
        } else if settings.englishModifier != .doubleShift {
            setEnglishOnly(settings.defaultLanguage == .english)
        }
        engine.lexicon.personalPersian = Set(dictionary.persianWords.map(PersianText.lookupKey))
        engine.lexicon.protectedEnglish = Set(dictionary.englishWords.map { $0.lowercased() })
    }

    // MARK: - IMKServerInput

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        guard let client = sender as? IMKTextInput else { return false }
        if event.type == .flagsChanged {
            return handleFlagsChanged(event: event, client: client)
        }
        guard event.type == .keyDown else { return false }
        return handleKeyInput(
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            client: client
        )
    }

    private func handleFlagsChanged(event: NSEvent, client: IMKTextInput) -> Bool {
        let settings = makeEngine().settings
        let flags = event.modifierFlags
        if settings.englishModifier == .capsLock {
            let isCapsOn = flags.contains(.capsLock)
            observedCapsLock = isCapsOn
            let targetEnglishOnly = (settings.defaultLanguage == .persian) ? isCapsOn : !isCapsOn
            if Self.englishOnly != targetEnglishOnly {
                if !buffer.isEmpty { flushBuffer(client: client) }
                setEnglishOnly(targetEnglishOnly)
            }
            return false
        } else if settings.englishModifier == .doubleShift {
            let keyCode = event.keyCode
            let timestamp = event.timestamp
            handleModifierChange(keyCode: keyCode, flags: flags, timestamp: timestamp, client: client)
            return false
        }
        return false
    }

    override func activateServer(_ sender: Any!) {
        reloadSettings()
        isPaused = false
        shiftDown = nil
        lastShiftTap = nil
        buffer = ""
        markedRange = NSRange(location: NSNotFound, length: 0)
        context = ConversionContext()
        translationTask?.cancel()
        translationTask = nil
        translationState = .idle
        lastConversion = nil
        awaitingForbiddenConfirmation = nil
        sessionLineBuffer = ""
        startShiftMonitor()
    }

    override func deactivateServer(_ sender: Any!) {
        shiftPollTimer?.invalidate()
        shiftPollTimer = nil
        flushBuffer(client: sender as? IMKTextInput)
        buffer = ""
        markedRange = NSRange(location: NSNotFound, length: 0)
        context = ConversionContext()
        shiftDown = nil
        lastShiftTap = nil
        translationTask?.cancel()
        translationTask = nil
        translationState = .idle
        lastConversion = nil
        awaitingForbiddenConfirmation = nil
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
        // Ask to receive key events and modifier flag changes.
        return Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        return nil
    }

    // MARK: - Key handling

    private func handleKeyInput(
        characters: String?,
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        client: IMKTextInput
    ) -> Bool {

        if shiftDown != nil || modifierFlags.contains(.shift) { shiftTapWasUsed = true }
        lastShiftTap = nil

        // If the active application is in the excluded/disabled list, stand down completely
        let currentAppID = currentAppBundleIdentifier(client: client)
        let settings = makeEngine().settings
        if settings.isAppDisabled(bundleID: currentAppID) {
            translationTask?.cancel()
            translationTask = nil
            translationState = .idle
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return false
        }

        // A paused input method must pass all keys to the client.
        if isPaused { return false }

        if settings.englishModifier == .capsLock {
            let isCapsOn = modifierFlags.contains(.capsLock)
            observedCapsLock = isCapsOn
            let targetEnglishOnly = (settings.defaultLanguage == .persian) ? isCapsOn : !isCapsOn
            if Self.englishOnly != targetEnglishOnly {
                if !buffer.isEmpty { flushBuffer(client: client) }
                setEnglishOnly(targetEnglishOnly)
            }
        } else if settings.englishModifier != .doubleShift {
            let targetEnglishOnly = (settings.defaultLanguage == .english)
            if Self.englishOnly != targetEnglishOnly {
                if !buffer.isEmpty { flushBuffer(client: client) }
                setEnglishOnly(targetEnglishOnly)
            }
        }

        if Self.englishOnly {
            // When Caps Lock is the active shortcut and physically engaged, macOS emits uppercase characters.
            // If Shift is NOT held, insert lowercase letters so the user gets normal English typing.
            if settings.englishModifier == .capsLock && modifierFlags.contains(.capsLock) {
                if !modifierFlags.contains(.shift) && !modifierFlags.contains(.command) && !modifierFlags.contains(.control) {
                    if let characters, characters.count == 1, let ch = characters.first, ch.isLetter {
                        let lower = String(ch).lowercased()
                        client.insertText(lower, replacementRange: NSRange(location: NSNotFound, length: 0))
                        sessionLineBuffer.append(Character(lower))
                        return true
                    }
                }
            }

            // Let the client handle the keys, including shortcuts, numbers,
            // punctuation, deletion and capital letters, without conversion.
            if !modifierFlags.contains(.command) && !modifierFlags.contains(.control),
               let characters, characters.count == 1,
               let character = characters.first, !character.isNewline,
               !character.isASCII || (character.asciiValue ?? 0) >= 32 {
                sessionLineBuffer.append(character)
            } else {
                sessionLineBuffer = ""
            }
            return false
        }

        // An edit or caret move invalidates the pending request.
        if case .translating = translationState, keyCode != 36 && keyCode != 76 && keyCode != 53 {
            translationTask?.cancel()
            translationTask = nil
            translationState = .idle
        }
        if keyCode != 51 && keyCode != 49 {
            lastConversion = nil
        }

        // Handle readyToSend state for non-Return/non-Escape keys:
        // if user types any character, backspaces, etc., reset translation state so they can edit.
        if case .readyToSend = translationState {
            if keyCode != 36 && keyCode != 76 && keyCode != 53 {
                translationState = .idle
            }
        }

        if awaitingForbiddenConfirmation != nil {
            if keyCode != 36 && keyCode != 76 && keyCode != 53 {
                awaitingForbiddenConfirmation = nil
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
            } else {
                fixLastDirectPersianWordIfNeeded(client: client)
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
            } else {
                fixLastDirectPersianWordIfNeeded(client: client)
            }
            if !isEnglishModifierActive(modifierFlags) { applyPunctuationSpacing(client: client) }
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
                if !buffer.isEmpty {
                    flushBuffer(client: client)
                } else {
                    fixLastDirectPersianWordIfNeeded(client: client)
                }
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
                } else {
                    fixLastDirectPersianWordIfNeeded(client: client)
                }
                if !isEnglishModifierActive(modifierFlags) { applyPunctuationSpacing(client: client) }
                sessionLineBuffer.append(" ")
                return false
            }
        }

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
              var character = characters.first else {
            return false
        }

        if modifierFlags.contains(.capsLock) && !modifierFlags.contains(.shift) {
            // If Caps Lock is physically on, normalize Latin keys to lowercase
            // so they convert to base Persian characters (e.g. 'h' -> 'ا', not shifted 'آ')
            if let lowered = character.lowercased().first {
                character = lowered
            }
        }

        if let ascii = character.asciiValue, (ascii < 32 || ascii == 127) {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            return false
        }

        if buffer.isEmpty && (character.isLetter || character.isNumber) {
            applyPunctuationSpacing(client: client)
            insertSpaceAfterPunctuationIfNeeded(before: character, client: client)
        }

        if settings.mode == .directPersian {
            if !buffer.isEmpty {
                flushBuffer(client: client)
            }
            if character.isNumber {
                fixLastDirectPersianWordIfNeeded(client: client)
                return handleDigitInput(character, client: client)
            }
            if let letter = PersianLayout.convert(character) {
                client.insertText(String(letter), replacementRange: NSRange(location: NSNotFound, length: 0))
                sessionLineBuffer.append(letter)
                return true
            }
            fixLastDirectPersianWordIfNeeded(client: client)
            sessionLineBuffer.append(character)
            return false
        }

        // Keep a complete technical token until a boundary. This lets the
        // engine see the digits and symbols before it converts a word.
        let technicalSymbol = "@/\\_#.:+~=&".contains(character)
        let technicalQuery = character == "?" && TechnicalPatterns.isHardTechnical(buffer)
        if isWordCharacter(character) || character.isNumber || technicalSymbol || technicalQuery {
            buffer.append(character)
            updateMarkedText(client: client)
            return true
        }

        // Anything else (punctuation, symbols) ends the word and is inserted
        // literally.
        if !buffer.isEmpty {
            flushBuffer(client: client)
        } else {
            fixLastDirectPersianWordIfNeeded(client: client)
        }

        // When the text around the caret is Persian, the punctuation that
        // belongs to it is written the Persian way: `?` becomes `؟`.
        if settings.usePersianPunctuation, context.isPersian,
           let mark = PersianText.persianPunctuationMark(for: character) {
            client.insertText(String(mark), replacementRange: NSRange(location: NSNotFound, length: 0))
            sessionLineBuffer.append(mark)
            if character == "?" {
                context = ConversionContext()
            }
            return true
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
        if undoLastConversion(client: client) { return true }
        if !sessionLineBuffer.isEmpty {
            sessionLineBuffer.removeLast()
        }
        return false
    }

    /// The raw modifier masks for the right-hand keys. AppKit exposes the
    /// left-hand flags as named constants but not the right-hand ones.
    private enum ModifierMask {
        static let rightCommand = NSEvent.ModifierFlags(rawValue: 0x10)
        static let rightOption = NSEvent.ModifierFlags(rawValue: 0x40)
        static let rightShift = NSEvent.ModifierFlags(rawValue: 0x04)
        static let leftShift = NSEvent.ModifierFlags(rawValue: 0x02)
    }

    private func isEnglishModifierActive(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch makeEngine().settings.englishModifier {
        case .none: return false
        case .rightCommand: return flags.contains(ModifierMask.rightCommand)
        case .rightOption: return flags.contains(ModifierMask.rightOption)
        case .rightShift: return flags.contains(ModifierMask.rightShift)
        case .leftShift: return flags.contains(ModifierMask.leftShift)
        case .doubleShift, .capsLock: return false
        }
    }

    private func startShiftMonitor() {
        shiftPollTimer?.invalidate()
        let initialFlags = CGEventSource.flagsState(.combinedSessionState)
        observedShift = initialFlags.contains(.maskShift)
        observedCapsLock = initialFlags.contains(.maskAlphaShift)
        shiftTapWasUsed = observedShift
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self else { return }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modifier = self.makeEngine().settings.englishModifier
            if modifier == .doubleShift {
                if let client = self.client() {
                    self.pollShiftState(flags, timestamp: ProcessInfo.processInfo.systemUptime, client: client)
                }
            } else if modifier == .capsLock {
                self.pollCapsLockState(flags)
            }
        }
        shiftPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func syncCapsLockState(_ isCapsOn: Bool, client: IMKTextInput? = nil) {
        observedCapsLock = isCapsOn
        let settings = makeEngine().settings
        let targetEnglishOnly = (settings.defaultLanguage == .persian) ? isCapsOn : !isCapsOn
        if Self.englishOnly != targetEnglishOnly {
            if !buffer.isEmpty, let c = client ?? self.client() {
                flushBuffer(client: c)
            }
            setEnglishOnly(targetEnglishOnly)
        }
    }

    func pollCapsLockState(_ flags: CGEventFlags) {
        let isCapsOn = flags.contains(.maskAlphaShift)
        guard isCapsOn != observedCapsLock else { return }
        syncCapsLockState(isCapsOn)
    }

    func pollShiftState(_ flags: CGEventFlags, timestamp: TimeInterval, client: IMKTextInput) {
        let isShiftDown = flags.contains(.maskShift)
        let hasOtherModifier = !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        if hasOtherModifier {
            lastShiftTap = nil
            if isShiftDown { shiftTapWasUsed = true }
        }
        guard isShiftDown != observedShift else { return }
        observedShift = isShiftDown
        var modifierFlags: NSEvent.ModifierFlags = isShiftDown ? [.shift, ModifierMask.leftShift] : []
        if flags.contains(.maskCommand) { modifierFlags.insert(.command) }
        if flags.contains(.maskControl) { modifierFlags.insert(.control) }
        if flags.contains(.maskAlternate) { modifierFlags.insert(.option) }
        handleModifierChange(keyCode: 56, flags: modifierFlags, timestamp: timestamp, client: client)
    }

    func handleModifierChange(keyCode: UInt16, flags: NSEvent.ModifierFlags, timestamp: TimeInterval, client: IMKTextInput) {
        guard makeEngine().settings.englishModifier == .doubleShift, !isPaused,
              !makeEngine().settings.isAppDisabled(bundleID: currentAppBundleIdentifier(client: client)) else {
            shiftDown = nil
            lastShiftTap = nil
            shiftTapWasUsed = false
            return
        }
        guard keyCode == 56 || keyCode == 60 else {
            if shiftDown != nil { shiftTapWasUsed = true }
            lastShiftTap = nil
            return
        }
        let mask = keyCode == 56 ? ModifierMask.leftShift : ModifierMask.rightShift
        let isDown = flags.contains(mask)
        if isDown {
            guard shiftDown == nil else { shiftTapWasUsed = true; return }
            shiftDown = keyCode
            shiftTapWasUsed = shiftTapWasUsed || !flags.intersection([.command, .control, .option]).isEmpty
        } else {
            guard shiftDown == keyCode else { lastShiftTap = nil; shiftTapWasUsed = false; return }
            shiftDown = nil
            let wasUsed = shiftTapWasUsed
            shiftTapWasUsed = false
            guard !wasUsed else { lastShiftTap = nil; return }
            if let previous = lastShiftTap, previous.key == keyCode,
               timestamp >= previous.time, timestamp - previous.time <= 0.4 {
                lastShiftTap = nil
                if !buffer.isEmpty { flushBuffer(client: client) }
                translationTask?.cancel()
                translationTask = nil
                translationState = .idle
                awaitingForbiddenConfirmation = nil
                lastConversion = nil
                context = ConversionContext()
                sessionLineBuffer = ""
                setEnglishOnly(!Self.englishOnly)
            } else {
                lastShiftTap = (keyCode, timestamp)
            }
        }
    }

    func setEnglishOnly(_ enabled: Bool) {
        guard Self.englishOnly != enabled else { return }
        Self.englishOnly = enabled
    }

    private func insertEnglishCharacter(_ characters: String?, client: IMKTextInput) -> Bool {
        guard let characters, characters.count == 1 else { return false }
        client.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    private func currentAppBundleIdentifier(client: IMKTextInput) -> String? {
        if let id = client.bundleIdentifier(), !id.isEmpty {
            return id
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Characters that may be part of a word.
    ///
    /// The Persian-only keys (`[ ] ; ' ,`) are included because they carry the
    /// Persian letters `ج چ ک گ و`. Hyphens (`-`) are included for kebab-case/slugs.
    private func isWordCharacter(_ character: Character) -> Bool {
        if character.isLetter { return true }
        if PersianLayout.persianOnlyKeys.contains(character) { return true }
        if character == "\u{200C}" { return true }
        if character == "-" { return true }
        return false
    }

    /// Handles digit key input according to the smart numbers setting and language context.
    private func handleDigitInput(_ character: Character, client: IMKTextInput) -> Bool {
        let settings = makeEngine().settings
        let targetRange = NSRange(location: NSNotFound, length: 0)

        // When smart numbers is enabled and we are inside Persian text, type Persian numerals (۱۲۳).
        // When at the start of text, in English context, or when disabled, type English digits (123).
        if settings.usePersianDigits && isPersianContext(client: client) {
            let digit = PersianText.persianDigit(for: character) ?? character
            client.insertText(String(digit), replacementRange: targetRange)
            sessionLineBuffer.append(digit)
            context.previousWasPersian = true
            return true
        } else {
            client.insertText(String(character), replacementRange: targetRange)
            sessionLineBuffer.append(character)
            if !context.isPersian {
                context.previousWasPersian = false
            }
            return true
        }
    }

    /// Determines whether the current insertion point is within Persian text.
    private func isPersianContext(client: IMKTextInput?) -> Bool {
        // 1. If sentence language is established:
        if context.sentenceLanguage == .persian { return true }
        if context.sentenceLanguage == .english { return false }

        // 2. If the previous word was Persian:
        if context.previousWasPersian { return true }

        // 3. Inspect recent characters in sessionLineBuffer:
        if let lastMeaningfulChar = sessionLineBuffer.reversed().first(where: {
            !$0.isWhitespace && !$0.isNumber && $0 != "." && $0 != "," && $0 != "/" && $0 != "-"
        }) {
            if PersianLayout.isPersianUnicode(lastMeaningfulChar) {
                return true
            }
            if lastMeaningfulChar.isASCII && lastMeaningfulChar.isLetter {
                return false
            }
        }

        // 4. If sessionLineBuffer is empty or only whitespace/numbers, inspect client text before caret:
        if let client = client {
            let caret = client.selectedRange().location
            if caret != NSNotFound && caret > 0 {
                let searchLength = min(caret, 100)
                let searchStart = caret - searchLength
                if let attrStr = client.attributedSubstring(from: NSRange(location: searchStart, length: searchLength)) {
                    let text = attrStr.string
                    if let lastChar = text.reversed().first(where: {
                        !$0.isWhitespace && !$0.isNumber && $0 != "." && $0 != "," && $0 != "/" && $0 != "-" && $0 != "\n"
                    }) {
                        if PersianLayout.isPersianUnicode(lastChar) {
                            return true
                        }
                        if lastChar.isASCII && lastChar.isLetter {
                            return false
                        }
                    }
                }
            }
        }

        // 5. Standalone, at the start of a line/sentence, or no Persian context:
        return false
    }

    // MARK: - Committing

    private func updateMarkedText(client: IMKTextInput) {
        // The preview shows the word the way it is going to be committed, so
        // an English word is never shown as Persian letters and a Persian word
        // is shown as Persian while it is being typed.
        let displayText = resolvePunctuationSeparatedToken(buffer)?.output ?? makeEngine().decide(token: buffer, context: context).output
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
        // Whether the text around the word is Persian — the digits and the
        // punctuation that belong to it follow the sentence, not the word.
        let persianContext = context.isPersian
        let outcome = resolvePunctuationSeparatedToken(token) ?? makeEngine().resolve(token: token, context: context)
        let composing = client.markedRange()
        let selected = client.selectedRange()
        let insertionStart = composing.location != NSNotFound ? composing.location : selected.location
        let decision = outcome.decision
        let targetRange = NSRange(location: NSNotFound, length: 0)

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
            context = outcome.context
            if insertionStart != NSNotFound {
                lastConversion = Conversion(latin: token, persian: output,
                                            range: NSRange(location: insertionStart, length: (output as NSString).length))
            }
        case .keepAsTyped(let text):
            var output = text
            if settings.usePersianDigits, persianContext, token.allSatisfy(\.isNumber) {
                output = PersianText.persianDigits(output)
            }
            if settings.usePersianPunctuation, persianContext, !TechnicalPatterns.isTechnical(token) {
                output = persianPunctuation(inSuffix: output)
            }
            client.insertText(output, replacementRange: targetRange)
            sessionLineBuffer.append(output)
            context = outcome.context
            lastConversion = nil
        }
        if !TechnicalPatterns.isTechnical(token), token.hasSuffix(".") {
            context = ConversionContext()
        }
    }

    /// Resolve words separated by a dot or colon when the token is not a URL,
    /// path, number, or another protected technical string.
    private func resolvePunctuationSeparatedToken(_ token: String) -> WordOutcome? {
        guard makeEngine().settings.fixPunctuationSpacing, !TechnicalPatterns.isTechnical(token) else { return nil }
        let characters = Array(token)
        guard characters.count >= 3,
              characters.indices.contains(where: { $0 > 0 && $0 + 1 < characters.count &&
                  ".:".contains(characters[$0]) && characters[$0 - 1].isLetter && characters[$0 + 1].isLetter }) else { return nil }
        var localContext = context
        var output = ""
        var word = ""
        for character in characters {
            if ".:".contains(character) {
                guard !word.isEmpty else { return nil }
                let outcome = makeEngine().resolve(token: word, context: localContext)
                output += outcome.output
                output.append(character)
                localContext = character == "." ? ConversionContext() : outcome.context
                word = ""
            } else {
                word.append(character)
            }
        }
        guard !word.isEmpty else { return nil }
        let last = makeEngine().resolve(token: word, context: localContext)
        output += last.output
        return WordOutcome(decision: .keepAsTyped(output), context: last.context)
    }

    /// Only edit text this controller just inserted and the client can verify.
    private func applyPunctuationSpacing(client: IMKTextInput) {
        let settings = makeEngine().settings
        guard settings.isEnabled, settings.fixPunctuationSpacing, !sessionLineBuffer.isEmpty,
              sessionLineBuffer.contains(where: { ".,،;؛:؟?!".contains($0) }),
              sessionLineBuffer.utf16.count <= 4096 else { return }
        let normalized = PunctuationSpacing.normalize(sessionLineBuffer, lexicon: makeEngine().lexicon)
        guard normalized != sessionLineBuffer else { return }
        let selection = client.selectedRange()
        let length = (sessionLineBuffer as NSString).length
        guard selection.location != NSNotFound, selection.length == 0, selection.location >= length else { return }
        let range = NSRange(location: selection.location - length, length: length)
        if let existing = client.attributedSubstring(from: range)?.string {
            guard existing == sessionLineBuffer else { return }
        }
        client.insertText(normalized, replacementRange: range)
        sessionLineBuffer = normalized
        lastConversion = nil
    }

    private func insertSpaceAfterPunctuationIfNeeded(before character: Character, client: IMKTextInput) {
        let settings = makeEngine().settings
        guard settings.isEnabled, settings.fixPunctuationSpacing,
              let last = sessionLineBuffer.last, ".,،;؛:؟?!".contains(last),
              sessionLineBuffer.utf16.count <= 4096 else { return }
        let proposed = sessionLineBuffer + String(character)
        let formatted = PunctuationSpacing.normalize(proposed, lexicon: makeEngine().lexicon)
        guard formatted == sessionLineBuffer + " " + String(character) else { return }
        let selection = client.selectedRange()
        let length = (sessionLineBuffer as NSString).length
        guard selection.location != NSNotFound, selection.length == 0, selection.location >= length else { return }
        let range = NSRange(location: selection.location - length, length: length)
        if let existing = client.attributedSubstring(from: range)?.string {
            guard existing == sessionLineBuffer else { return }
        }
        client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        sessionLineBuffer.append(" ")
    }

    /// In direct Persian mode (or when Persian characters were inserted directly),
    /// checks if the word immediately before the boundary has transposed characters and fixes it.
    private func fixLastDirectPersianWordIfNeeded(client: IMKTextInput?) {
        guard !isPaused else { return }
        let engine = makeEngine()
        let settings = engine.settings
        guard settings.isEnabled, settings.fixTransposedCharacters else { return }
        guard let client else { return }

        // Extract trailing Persian letters from sessionLineBuffer
        var wordStart = sessionLineBuffer.endIndex
        while wordStart > sessionLineBuffer.startIndex {
            let prev = sessionLineBuffer.index(before: wordStart)
            let ch = sessionLineBuffer[prev]
            if PersianLayout.isPersianUnicode(ch) {
                wordStart = prev
            } else {
                break
            }
        }

        let lastWord = String(sessionLineBuffer[wordStart...])
        guard lastWord.count >= 3,
              let corrected = engine.transposedPersianWord(for: lastWord),
              corrected != lastWord else {
            return
        }

        let caret = client.selectedRange().location
        let oldNSLen = (lastWord as NSString).length
        guard caret != NSNotFound, caret >= oldNSLen else { return }
        let replaceRange = NSRange(location: caret - oldNSLen, length: oldNSLen)
        if let existing = client.attributedSubstring(from: replaceRange)?.string {
            guard existing == lastWord else { return }
        }
        client.insertText(corrected, replacementRange: replaceRange)
        sessionLineBuffer.replaceSubrange(wordStart..., with: corrected)
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
        guard caret != NSNotFound, caret == conversion.range.location + conversion.range.length else { return false }
        if let existing = client.attributedSubstring(from: conversion.range)?.string {
            guard existing == conversion.persian else { return false }
        }
        if sessionLineBuffer.hasSuffix(conversion.persian) {
            sessionLineBuffer.removeLast(conversion.persian.count)
            sessionLineBuffer.append(conversion.latin)
        }
        client.insertText(conversion.latin, replacementRange: conversion.range)
        lastConversion = nil
        context = ConversionContext(previousWasPersian: false, previousPersianWord: nil)
        return true
    }

    // MARK: - Translation & Send Interception on Enter

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
        } else {
            fixLastDirectPersianWordIfNeeded(client: client)
        }

        applyPunctuationSpacing(client: client)

        let lineText = extractCurrentLineText(client: client)
        let settings = makeEngine().settings
        let dictionary = settingsStore.dictionary

        // Check for forbidden words to prevent accidental sending
        if settings.checkForForbiddenWords && !dictionary.forbiddenWords.isEmpty {
            let matched = ForbiddenWordsDetector.findMatches(in: lineText, forbiddenWords: dictionary.forbiddenWords)
            if !matched.isEmpty {
                switch settings.forbiddenWordsAction {
                case .block:
                    NSSound.beep()
                    return true // Block completely
                case .requireConfirmation:
                    if let pending = awaitingForbiddenConfirmation, pending.line == lineText {
                        // Second Enter: user confirmed sending despite forbidden words!
                        awaitingForbiddenConfirmation = nil
                        // Proceed below to translation or dispatch
                    } else {
                        // First Enter: intercept and require a second Enter
                        awaitingForbiddenConfirmation = (detectedWords: matched, line: lineText)
                        NSSound.beep()
                        return true
                    }
                }
            } else {
                awaitingForbiddenConfirmation = nil
            }
        } else {
            awaitingForbiddenConfirmation = nil
        }

        guard settings.translation.isEnabled,
              !settings.translation.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sessionLineBuffer = ""
            return false
        }

        guard let candidate = extractTextForTranslation(client: client, translationSettings: settings.translation) else {
            sessionLineBuffer = ""
            return false
        }

        let textToTranslate = candidate.text
        let originalLineText = candidate.originalLine
        let rangeToReplace = candidate.range
        let action = candidate.action

        // Do not replace a range the client cannot verify.
        guard rangeToReplace.location != NSNotFound,
              client.selectedRange() == NSRange(location: rangeToReplace.location + rangeToReplace.length, length: 0),
              client.attributedSubstring(from: rangeToReplace)?.string == originalLineText else {
            NSSound.beep()
            return true
        }
        let requestID = UUID()
        translationState = .translating(id: requestID)

        translationTask = Task { @MainActor [weak self, weak client] in
            guard let self = self else { return }
            do {
                let processed = try await self.translationProcessor(textToTranslate, action.systemPrompt, settings.translation)
                guard case .translating(let activeID) = self.translationState, activeID == requestID, !Task.isCancelled else { return }
                guard let currentClient = client else {
                    self.translationState = .idle
                    self.translationTask = nil
                    return
                }

                guard currentClient.selectedRange() == NSRange(location: rangeToReplace.location + rangeToReplace.length, length: 0),
                      currentClient.attributedSubstring(from: rangeToReplace)?.string == originalLineText else {
                    self.translationState = .idle
                    self.translationTask = nil
                    return
                }
                currentClient.insertText(processed, replacementRange: rangeToReplace)

                let newLength = (processed as NSString).length
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
                    translatedText: processed,
                    range: newRange
                )
                self.sessionLineBuffer = processed
                self.translationTask = nil
            } catch {
                guard case .translating(let activeID) = self.translationState, activeID == requestID else { return }
                self.translationTask = nil
                NSLog("AutoType: AI action failed")
                self.translationState = .idle
                NSSound.beep()
            }
        }

        // Consume this first Enter so the message is not submitted yet.
        return true
    }

    private func handleEscape(client: IMKTextInput) -> Bool {
        if awaitingForbiddenConfirmation != nil {
            awaitingForbiddenConfirmation = nil
            return true
        }
        if case .translating = translationState {
            translationTask?.cancel()
            translationTask = nil
            translationState = .idle
            return true
        }
        if case .readyToSend(let originalText, let translatedText, let range) = translationState {
            guard client.selectedRange() == NSRange(location: range.location + range.length, length: 0),
                  client.attributedSubstring(from: range)?.string == translatedText else {
                translationState = .idle
                return false
            }
            client.insertText(originalText, replacementRange: range)
            translationState = .idle
            sessionLineBuffer = originalText
            return true
        }
        return false
    }

    private func extractCurrentLineText(client: IMKTextInput) -> String {
        let caret = client.selectedRange().location
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
                if !lineText.isEmpty {
                    return lineText
                }
            }
        }
        return sessionLineBuffer.trimmingCharacters(in: .newlines)
    }

    private func extractTextForTranslation(
        client: IMKTextInput,
        translationSettings: TranslationSettings
    ) -> (text: String, originalLine: String, range: NSRange, action: AIAction)? {
        let caret = client.selectedRange().location
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
                if let extraction = translationSettings.extractActionAndBody(from: lineText) {
                    let offsetInPrefix = (String(fullPrefix[..<lineStartIndex]) as NSString).length
                    let absoluteLocation = searchStart + offsetInPrefix
                    let length = (String(lineSubstring) as NSString).length
                    return (extraction.body, lineText, NSRange(location: absoluteLocation, length: length), extraction.action)
                }
            }
        }

        // Fallback to sessionLineBuffer if attributedSubstring is unavailable
        let trimmedBuffer = sessionLineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let extraction = translationSettings.extractActionAndBody(from: trimmedBuffer) {
            let length = (sessionLineBuffer as NSString).length
            let location = (caret != NSNotFound && caret >= length) ? caret - length : NSNotFound
            return (extraction.body, trimmedBuffer, NSRange(location: location, length: length), extraction.action)
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
        if !isPaused && !buffer.isEmpty { flushBuffer(client: client()) }
        isPaused.toggle()
        translationTask?.cancel()
        translationTask = nil
        translationState = .idle
        awaitingForbiddenConfirmation = nil
        lastConversion = nil
        context = ConversionContext()
        sessionLineBuffer = ""
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
