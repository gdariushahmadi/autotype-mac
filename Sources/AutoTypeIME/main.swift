import AppKit
import InputMethodKit
import AutoTypeCore

/// Runs the self test: the dictionaries, the settings and a whole sentence
/// typed through the real controller.
func runSelfTest() -> Int32 {
    let store = SettingsStore.shared
    let lexicon: Lexicon
    do {
        lexicon = try AutoTypeResources.loadLexicon()
    } catch {
        FileHandle.standardError.write("AutoType self test failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        return 1
    }

    let dictionary = store.dictionary
    lexicon.personalPersian = Set(dictionary.persianWords.map(PersianText.lookupKey))
    lexicon.protectedEnglish = Set(dictionary.englishWords.map { $0.lowercased() })

    print("AutoType self test")
    print("  persian words:  \(lexicon.persianCount)")
    print("  english words: \(lexicon.englishCount)")
    print("  settings file:  \(SettingsStore.settingsURL.path)")
    print("  mode:           \(store.settings.mode.rawValue)")
    print("  priority:       \(store.settings.priority.rawValue)")
    print("  personal words: \(dictionary.persianWords.count) persian, \(dictionary.englishWords.count) english")

    var failures = 0

    func expect(_ actual: String, _ expected: String, _ what: String) {
        if actual == expected {
            print("  ✓ \(what)")
        } else {
            print("  ✗ \(what) — expected “\(expected)”, got “\(actual)”")
            failures += 1
        }
    }

    // The engine on its own (tested with automatic mode).
    var testSettings = ConversionSettings()
    testSettings.mode = .automatic
    testSettings.priority = .persianFirst
    let engine = ConversionEngine(lexicon: lexicon, settings: testSettings)
    expect(engine.decide(token: "sghl").output, "سلام", "sghl → سلام")
    expect(engine.decide(token: ";jhf").output, "کتاب", ";jhf → کتاب")
    expect(engine.decide(token: "hello").output, "hello", "hello stays English")
    expect(engine.decide(token: "test@example.com").output, "test@example.com", "an e-mail address survives")

    // The whole typing flow, through the real controller.
    //
    // The controller is created without a server: InputMethodKit only accepts
    // a real client proxy there, and the key handling takes the client as an
    // argument anyway.
    let controller = Controller()
    controller.loadedEngine = engine
    let client = MockTextInput()

    func type(_ text: String) {
        type(text, on: controller, client: client)
    }

    func type(_ text: String, on controller: Controller, client: MockTextInput, modifiers: NSEvent.ModifierFlags = []) {
        for character in text {
            let keyCode = character == " " ? 49 : 0
            let handled = controller.inputText(
                String(character),
                key: keyCode,
                modifiers: Int(modifiers.rawValue),
                client: client
            )
            if !handled {
                // A real client inserts the key itself when the input
                // method passes the event on.
                client.insertText(
                    String(character),
                    replacementRange: NSRange(location: NSNotFound, length: 0)
                )
            }
        }
    }

    func pressBackspace(on controller: Controller, client: MockTextInput) {
        let handled = controller.inputText(
            "\u{8}",
            key: 51,
            modifiers: 0,
            client: client
        )
        if !handled {
            client.deleteBackward()
        }
    }

    type("sghl ")
    expect(client.text, "سلام ", "a typed Persian word is committed")

    type("hello ")
    expect(client.text, "سلام hello ", "an English word is left alone")

    type(";jhfih ")
    expect(client.text, "سلام hello کتاب‌ها ", "a plural keeps its ZWNJ")

    type("ldv,n ")
    expect(client.text, "سلام hello کتاب‌ها می‌رود ", "a verb prefix keeps its ZWNJ")

    type("test@example.com ")
    expect(client.text, "سلام hello کتاب‌ها می‌رود test@example.com ", "a technical string survives")

    let sentenceClient = MockTextInput()
    let sentenceController = Controller()
    sentenceController.loadedEngine = engine
    type("offline ", on: sentenceController, client: sentenceClient)
    type("and", on: sentenceController, client: sentenceClient)
    expect(sentenceClient.markedText, "and", "an ambiguous word stays English in the preview")
    type(" a new message ", on: sentenceController, client: sentenceClient)
    expect(sentenceClient.text, "offline and a new message ", "offline sets the language for the English sentence")

    let persianClient = MockTextInput()
    let persianController = Controller()
    persianController.loadedEngine = engine
    type("sghl and ", on: persianController, client: persianClient)
    expect(persianClient.text, "سلام شدی ", "the same keys follow a Persian sentence")

    let punctuationClient = MockTextInput()
    let punctuationController = Controller()
    punctuationController.loadedEngine = engine
    type("sghl ?o", on: punctuationController, client: punctuationClient)
    expect(punctuationClient.text, "سلام؟ خ", "spacing is corrected as the next word starts")
    type(",f ", on: punctuationController, client: punctuationClient)
    expect(punctuationClient.text, "سلام؟ خوب ", "punctuation spaces are corrected after the word")
    let colonClient = MockTextInput()
    let colonController = Controller()
    colonController.loadedEngine = engine
    type("sghl:lk ", on: colonController, client: colonClient)
    expect(colonClient.text, "سلام: من ", "colon separates two typed Persian words")
    let dotClient = MockTextInput()
    let dotController = Controller()
    dotController.loadedEngine = engine
    type("sghl.o,f ", on: dotController, client: dotClient)
    expect(dotClient.text, "سلام. خوب ", "a dot separates two typed Persian words")
    var spacingOffSettings = testSettings
    spacingOffSettings.fixPunctuationSpacing = false
    let spacingOffClient = MockTextInput()
    let spacingOffController = Controller()
    spacingOffController.loadedEngine = ConversionEngine(lexicon: lexicon, settings: spacingOffSettings)
    type("sghl ?o,f ", on: spacingOffController, client: spacingOffClient)
    expect(spacingOffClient.text, "سلام ؟خوب ", "punctuation spacing can be disabled")

    // A trailing comma follows the Persian word it belongs to.
    type("sghl, ")
    expect(client.text, "سلام hello کتاب‌ها می‌رود test@example.com سلام، ", "a trailing comma becomes a Persian comma")

    // A word that only has a Persian reading is Persian, wherever it stands.
    let functionClient = MockTextInput()
    let functionController = Controller()
    functionController.loadedEngine = engine
    type("hc ", on: functionController, client: functionClient)
    expect(functionClient.text, "از ", "«از» is Persian even at the start of a sentence")

    // The question mark is written the Persian way inside a Persian sentence.
    type("sghl?", on: functionController, client: functionClient)
    expect(functionClient.text, "از سلام؟", "the question mark becomes a Persian one")

    // The preview shows the word the way it will be committed.
    let previewClient = MockTextInput()
    let previewController = Controller()
    previewController.loadedEngine = engine
    type("www", on: previewController, client: previewClient)
    expect(previewClient.markedText, "www", "the preview of an English word stays Latin")

    // Backspace restores the Latin keys after the boundary is deleted.
    let undoClient = MockTextInput()
    let undoController = Controller()
    undoController.loadedEngine = engine
    type("sghl ", on: undoController, client: undoClient)
    expect(undoClient.text, "سلام ", "a word is converted")
    pressBackspace(on: undoController, client: undoClient)
    expect(undoClient.text, "سلام", "the first backspace deletes the space")
    pressBackspace(on: undoController, client: undoClient)
    expect(undoClient.text, "sghl", "the second backspace restores the Latin keys")

    // Holding the right ⌘ types plain English.
    let englishClient = MockTextInput()
    let englishController = Controller()
    englishController.loadedEngine = engine
    type("sghl", on: englishController, client: englishClient, modifiers: NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10))
    expect(englishClient.text, "sghl", "the English modifier types plain English")

    let technicalClient = MockTextInput()
    let technicalController = Controller()
    technicalController.loadedEngine = engine
    type("sghl@example.com sghl+tag@example.com sghl123 /sghl/file sghl.com https://sghl.com/?sghl=123 ", on: technicalController, client: technicalClient)
    expect(technicalClient.text, "sghl@example.com sghl+tag@example.com sghl123 /sghl/file sghl.com https://sghl.com/?sghl=123 ", "technical tokens stay intact")

    let modifierClient = MockTextInput()
    let modifierController = Controller()
    modifierController.loadedEngine = engine
    let controlHandled = modifierController.inputText("a", key: 0, modifiers: Int(NSEvent.ModifierFlags.control.rawValue), client: modifierClient)
    expect(controlHandled ? "handled" : "passed", "passed", "Control shortcuts pass through")
    let leftCommandHandled = modifierController.inputText("a", key: 0, modifiers: Int(NSEvent.ModifierFlags.command.rawValue | 0x08), client: modifierClient)
    expect(leftCommandHandled ? "handled" : "passed", "passed", "left Command shortcuts pass through")

    let modifierCases: [(EnglishModifier, UInt, UInt)] = [
        (.rightOption, NSEvent.ModifierFlags.option.rawValue | 0x40, NSEvent.ModifierFlags.option.rawValue | 0x20),
        (.rightShift, NSEvent.ModifierFlags.shift.rawValue | 0x04, NSEvent.ModifierFlags.shift.rawValue | 0x02),
        (.leftShift, NSEvent.ModifierFlags.shift.rawValue | 0x02, NSEvent.ModifierFlags.shift.rawValue | 0x04),
    ]
    for (choice, activeFlags, otherFlags) in modifierCases {
        var localSettings = testSettings
        localSettings.englishModifier = choice
        let localEngine = ConversionEngine(lexicon: lexicon, settings: localSettings)
        let activeClient = MockTextInput()
        let activeController = Controller()
        activeController.loadedEngine = localEngine
        type("sghl", on: activeController, client: activeClient, modifiers: NSEvent.ModifierFlags(rawValue: activeFlags))
        expect(activeClient.text, "sghl", "\(choice.displayName) types English")
        let otherClient = MockTextInput()
        let otherController = Controller()
        otherController.loadedEngine = localEngine
        type("sghl", on: otherController, client: otherClient, modifiers: NSEvent.ModifierFlags(rawValue: otherFlags))
        type(" ", on: otherController, client: otherClient)
        expect(otherClient.text, "سلام ", "the opposite modifier does not select English")
    }

    var doubleSettings = testSettings
    doubleSettings.englishModifier = .doubleShift
    let doubleEngine = ConversionEngine(lexicon: lexicon, settings: doubleSettings)
    let doubleClient = MockTextInput()
    let doubleController = Controller()
    doubleController.loadedEngine = doubleEngine
    let shiftFlags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x02)
    func shiftTap(_ time: TimeInterval, on controller: Controller = doubleController, client: MockTextInput = doubleClient) {
        controller.handleModifierChange(keyCode: 56, flags: shiftFlags, timestamp: time, client: client)
        controller.handleModifierChange(keyCode: 56, flags: [], timestamp: time + 0.05, client: client)
    }
    shiftTap(1)
    shiftTap(1.2)
    expect(doubleController.isEnglishOnly ? "on" : "off", "on", "double Shift enables English-only typing")
    type("sghl xqzpt 123!? ", on: doubleController, client: doubleClient)
    expect(doubleClient.text, "sghl xqzpt 123!? ", "English-only typing keeps unknown codes and punctuation")
    let secondClient = MockTextInput()
    let secondController = Controller()
    secondController.loadedEngine = doubleEngine
    expect(secondController.isEnglishOnly ? "on" : "off", "on", "English-only mode follows the active application")
    shiftTap(2, on: secondController, client: secondClient)
    shiftTap(2.2, on: secondController, client: secondClient)
    expect(doubleController.isEnglishOnly ? "on" : "off", "off", "double Shift restores automatic typing")
    type("sghl ", on: secondController, client: secondClient)
    expect(secondClient.text, "سلام ", "Persian conversion resumes")
    shiftTap(3)
    type("a", on: doubleController, client: doubleClient)
    shiftTap(3.2)
    expect(doubleController.isEnglishOnly ? "on" : "off", "off", "a key between Shift taps cancels the shortcut")
    doubleController.handleModifierChange(keyCode: 56, flags: shiftFlags, timestamp: 4, client: doubleClient)
    type("A", on: doubleController, client: doubleClient, modifiers: shiftFlags)
    doubleController.handleModifierChange(keyCode: 56, flags: [], timestamp: 4.05, client: doubleClient)
    shiftTap(4.2)
    expect(doubleController.isEnglishOnly ? "on" : "off", "off", "Shift used for a capital letter is not a tap")
    shiftTap(5)
    shiftTap(6)
    expect(doubleController.isEnglishOnly ? "on" : "off", "off", "slow Shift taps do not toggle")

    let pollClient = MockTextInput()
    let pollController = Controller()
    pollController.loadedEngine = doubleEngine
    pollController.pollShiftState(.maskShift, timestamp: 10, client: pollClient)
    pollController.pollShiftState([], timestamp: 10.05, client: pollClient)
    pollController.pollShiftState(.maskShift, timestamp: 10.15, client: pollClient)
    pollController.pollShiftState([], timestamp: 10.2, client: pollClient)
    expect(pollController.isEnglishOnly ? "on" : "off", "on", "polled Shift state enables English-only typing")
    pollController.pollShiftState(.maskShift, timestamp: 11, client: pollClient)
    pollController.pollShiftState([], timestamp: 11.05, client: pollClient)
    pollController.pollShiftState(.maskShift, timestamp: 11.15, client: pollClient)
    pollController.pollShiftState([], timestamp: 11.2, client: pollClient)
    expect(pollController.isEnglishOnly ? "on" : "off", "off", "polled Shift state restores automatic typing")

    // Caps Lock shortcut test
    var capsSettings = testSettings
    capsSettings.englishModifier = .capsLock
    capsSettings.defaultLanguage = .persian
    let capsEngine = ConversionEngine(lexicon: lexicon, settings: capsSettings)
    let capsClient = MockTextInput()
    let capsController = Controller()
    capsController.loadedEngine = capsEngine
    capsController.pollCapsLockState(.maskAlphaShift)
    expect(capsController.isEnglishOnly ? "on" : "off", "on", "Caps Lock ON enables English-only typing")
    type("sghl ", on: capsController, client: capsClient, modifiers: .capsLock)
    expect(capsClient.text, "sghl ", "Caps Lock English typing inserts lowercase English")
    capsController.pollCapsLockState([])
    expect(capsController.isEnglishOnly ? "on" : "off", "off", "Caps Lock OFF restores Persian typing")
    type("sghl ", on: capsController, client: capsClient)
    expect(capsClient.text, "sghl سلام ", "Persian conversion resumes after Caps Lock OFF")

    // Default English test
    var defEngSettings = testSettings
    defEngSettings.englishModifier = .capsLock
    defEngSettings.defaultLanguage = .english
    let defEngEngine = ConversionEngine(lexicon: lexicon, settings: defEngSettings)
    let defEngClient = MockTextInput()
    let defEngController = Controller()
    defEngController.loadedEngine = defEngEngine
    defEngController.syncCapsLockState(false)
    expect(defEngController.isEnglishOnly ? "on" : "off", "on", "Default English starts with English-only typing")
    defEngController.pollCapsLockState(.maskAlphaShift)
    expect(defEngController.isEnglishOnly ? "on" : "off", "off", "Caps Lock with Default English switches to Persian")
    type("sghl ", on: defEngController, client: defEngClient, modifiers: .capsLock)
    expect(defEngClient.text, "سلام ", "Converted to Persian when Caps Lock is active in Default English mode")

    let pauseClient = MockTextInput()
    let pauseController = Controller()
    pauseController.loadedEngine = engine
    pauseController.togglePause(nil)
    let pausedReturn = pauseController.inputText("\r", key: 36, modifiers: 0, client: pauseClient)
    let pausedSpace = pauseController.inputText(" ", key: 49, modifiers: Int(NSEvent.ModifierFlags.shift.rawValue), client: pauseClient)
    expect(pausedReturn || pausedSpace ? "handled" : "passed", "passed", "pause passes Return and Shift-Space through")

    // Use a delayed local response to check that edits cannot be overwritten.
    var aiSettings = testSettings
    aiSettings.translation.isEnabled = true
    aiSettings.translation.apiKey = "self-test"
    let aiEngine = ConversionEngine(lexicon: lexicon, settings: aiSettings)
    let aiClient = MockTextInput()
    let aiController = Controller()
    aiController.loadedEngine = aiEngine
    aiController.translationProcessor = { _, _, _ in
        try await Task.sleep(nanoseconds: 100_000_000)
        return "translated"
    }
    aiClient.insertText("/tr hello", replacementRange: NSRange(location: NSNotFound, length: 0))
    _ = aiController.inputText("\r", key: 36, modifiers: 0, client: aiClient)
    aiClient.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    expect(aiClient.text, "/tr hello!", "AI response does not replace externally edited text")

    let editClient = MockTextInput()
    let editController = Controller()
    editController.loadedEngine = aiEngine
    editController.translationProcessor = { _, _, _ in
        try await Task.sleep(nanoseconds: 100_000_000)
        return "translated"
    }
    editClient.insertText("/tr hello", replacementRange: NSRange(location: NSNotFound, length: 0))
    _ = editController.inputText("\r", key: 36, modifiers: 0, client: editClient)
    type("x", on: editController, client: editClient)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    expect(editClient.text, "/tr helloط", "typing cancels the pending AI response")

    let successClient = MockTextInput()
    let successController = Controller()
    successController.loadedEngine = aiEngine
    successController.translationProcessor = { _, _, _ in "translated" }
    successClient.insertText("/tr hello", replacementRange: NSRange(location: NSNotFound, length: 0))
    _ = successController.inputText("\r", key: 36, modifiers: 0, client: successClient)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    expect(successClient.text, "translated", "AI response replaces the unchanged line")
    _ = successController.inputText("\u{1b}", key: 53, modifiers: 0, client: successClient)
    expect(successClient.text, "/tr hello", "Escape restores the original line")

    if failures == 0 {
        print("All self test checks passed.")
    } else {
        print("\(failures) self test checks failed.")
    }
    return failures == 0 ? 0 : 1
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

// The input method is a background agent: no Dock icon, no menu bar of its
// own. macOS starts it when the user selects AutoType as an input source.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// Creating the server registers the input method with the window server and
// opens the connection that applications use to talk to it.
let inputMethod = InputMethod()
_ = inputMethod.server

application.run()
