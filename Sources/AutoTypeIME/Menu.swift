import AppKit
import AutoTypeCore

/// The commands AutoType adds to the input menu in the menu bar.
extension Controller {

    /// The menu shown when the user clicks the input menu while AutoType
    /// is the active input source.
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settings = makeEngine().settings

        // A quiet header, so the menu says what it belongs to.
        let header = NSMenuItem(title: "AutoType \(Self.version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(
            title: "Convert Persian words",
            action: #selector(toggleAutoTypeEnabled),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let auto = NSMenuItem(title: "Automatic Persian", action: #selector(setAutomaticMode), keyEquivalent: "")
        auto.target = self
        auto.state = settings.mode == .automatic ? .on : .off
        menu.addItem(auto)

        let direct = NSMenuItem(title: "Direct Persian", action: #selector(setDirectMode), keyEquivalent: "")
        direct.target = self
        direct.state = settings.mode == .directPersian ? .on : .off
        menu.addItem(direct)

        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: isPaused ? "Resume AutoType" : "Pause AutoType",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let convertWord = NSMenuItem(
            title: "Convert Word Before Cursor",
            action: #selector(convertWordBeforeCursor),
            keyEquivalent: ""
        )
        convertWord.target = self
        menu.addItem(convertWord)

        let convertSelection = NSMenuItem(
            title: "Convert Selection to Persian",
            action: #selector(convertSelection),
            keyEquivalent: ""
        )
        convertSelection.target = self
        menu.addItem(convertSelection)

        let addToDictionary = NSMenuItem(
            title: "Add Selection to Dictionary",
            action: #selector(addSelectionToDictionary),
            keyEquivalent: ""
        )
        addToDictionary.target = self
        menu.addItem(addToDictionary)

        menu.addItem(.separator())

        let preferences = NSMenuItem(
            title: "AutoType Settings…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        preferences.target = self
        menu.addItem(preferences)

        menu.addItem(.separator())

        let restart = NSMenuItem(
            title: "Restart AutoType (Reload)",
            action: #selector(restartInputMethod),
            keyEquivalent: ""
        )
        restart.target = self
        menu.addItem(restart)

        return menu
    }

    /// The version shown in the header of the menu.
    static var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    // The menu items carry plain `@objc` actions. InputMethodKit looks them
    // up on the controller and calls them with the command dictionary, so no
    // separate command router is needed.

    @objc func restartInputMethod(_ sender: Any?) {
        exit(0)
    }

    @objc func toggleAutoTypeEnabled(_ sender: Any?) {
        var settings = settingsStore.settings
        settings.isEnabled.toggle()
        settingsStore.save(settings)
        reloadSettings()
    }

    @objc func setAutomaticMode(_ sender: Any?) {
        var settings = settingsStore.settings
        settings.mode = .automatic
        settingsStore.save(settings)
        reloadSettings()
    }

    @objc func setDirectMode(_ sender: Any?) {
        var settings = settingsStore.settings
        settings.mode = .directPersian
        settingsStore.save(settings)
        reloadSettings()
    }
}
