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

    // A trailing comma follows the Persian word it belongs to.
    type("sghl, ")
    expect(client.text, "سلام hello کتاب‌ها می‌رود test@example.com سلام، ", "a trailing comma becomes a Persian comma")

    // Backspace over a converted word deletes characters normally.
    let undoClient = MockTextInput()
    let undoController = Controller()
    undoController.loadedEngine = engine
    type("sghl ", on: undoController, client: undoClient)
    expect(undoClient.text, "سلام ", "a word is converted")
    pressBackspace(on: undoController, client: undoClient)
    expect(undoClient.text, "سلام", "the first backspace deletes the space")
    pressBackspace(on: undoController, client: undoClient)
    expect(undoClient.text, "سلا", "the second backspace deletes the last character")

    // Holding the right ⌘ types plain English.
    let englishClient = MockTextInput()
    let englishController = Controller()
    englishController.loadedEngine = engine
    type("sghl", on: englishController, client: englishClient, modifiers: NSEvent.ModifierFlags(rawValue: 1 << 18))
    expect(englishClient.text, "sghl", "the English modifier types plain English")

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
