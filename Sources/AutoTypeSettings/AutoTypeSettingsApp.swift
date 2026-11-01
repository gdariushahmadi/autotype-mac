import SwiftUI
import AppKit
import ApplicationServices
import AutoTypeCore

@main
struct AutoTypeSettingsApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = SettingsModel()

    var body: some Scene {
        // The menu bar icon: a small menu with the state of AutoType and the
        // two settings that are worth reaching for in a single click.
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(model)
        } label: {
            MenuBarLabel(symbol: model.settings.mode == .directPersian
                         ? "character.bubble.fill"
                         : "character.book.closed")
        }
        .menuBarExtraStyle(.menu)

        // The settings themselves, in a window of their own.
        Window("AutoType Settings", id: AppRouter.settingsWindowID) {
            SettingsView()
                .environmentObject(model)
        }
        .defaultSize(width: 1000, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            // ⌘, opens the settings window, the way it does in every other
            // macOS app.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppRouter.shared.openSettings?()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// The picture in the menu bar.
///
/// It also holds on to the action that opens the settings window, so that the
/// parts of the app that are not SwiftUI views — the input method's
/// “AutoType Settings…” item, for one — can open the same window.
private struct MenuBarLabel: View {

    @Environment(\.openWindow) private var openWindow

    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("AutoType")
            .onAppear {
                AppRouter.shared.openSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: AppRouter.settingsWindowID)
                }

                // The input method opens the app with `--open-settings`, so
                // that the window comes up with the app instead of leaving the
                // user in front of a menu bar icon.
                if CommandLine.arguments.contains("--open-settings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        AppRouter.shared.openSettings?()
                    }
                }
            }
    }
}

/// Wires the parts of AutoType that live outside the SwiftUI scene.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A service request can arrive while the app is still starting, so the
        // provider is registered as early as possible.
        ServiceProvider.register(in: notification.object as? NSApplication)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `--section <name>` opens the window on one part of it, so that the
        // layout of every part can be looked at.
        if let index = CommandLine.arguments.firstIndex(of: "--section"),
           index + 1 < CommandLine.arguments.count,
           let section = SettingsSection(rawValue: CommandLine.arguments[index + 1]) {
            AppRouter.shared.pendingSection = section
        }

        // `--diagnose` prints what the app managed to open and then quits.
        // It is the same kind of check the input method does with `--self-test`.
        // `--slow` gives the window more time to settle before the report.
        if CommandLine.arguments.contains("--diagnose") {
            let settle = CommandLine.arguments.contains("--slow") ? 6.0 : 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                var report = "active=\(NSApp.isActive)\n"
                for window in NSApp.windows {
                    let size = window.frame.size
                    report += "window: class=\(type(of: window)) title=\"\(window.title)\" size=\(Int(size.width))x\(Int(size.height)) visible=\(window.isVisible)\n"
                }
                report += "status: \(InputSourceStatus.current().title)\n"
                report += Self.accessibilityReport()
                report += Self.outlineReport()
                FileHandle.standardError.write(report.data(using: .utf8)!)

                // `--snapshot <path>` writes a picture of the window, so the
                // layout can be looked at without a screen recording.
                if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
                   index + 1 < CommandLine.arguments.count {
                    Self.writeSnapshot(to: CommandLine.arguments[index + 1])
                }
                NSApp.terminate(nil)
                // A window that is still opening can hold the quit back, so
                // the check always ends.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    exit(0)
                }
            }
        }

        // `--menu-check` opens the menu behind the menu bar icon and lists
        // what is in it, so that an empty or nameless menu cannot slip by.
        if CommandLine.arguments.contains("--menu-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Self.openMenuBarMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    var report = Self.menuReport()
                    // The menu is a window of its own, so it can be written
                    // down as a picture as well.
                    if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
                       index + 1 < CommandLine.arguments.count {
                        Self.writeMenuSnapshot(to: CommandLine.arguments[index + 1])
                        report += "menu window: \(Self.menuWindowDescription())\n"
                    }
                    FileHandle.standardError.write(report.data(using: .utf8)!)
                    exit(0)
                }
            }
        }
    }

    // MARK: - The menu behind the icon

    /// Writes a picture of the open menu.
    private static func writeMenuSnapshot(to path: String) {
        for window in NSApp.windows {
            guard String(describing: type(of: window)).contains("Menu"),
                  let view = window.contentView else { continue }
            write(view, to: path)
            return
        }
    }

    private static func menuWindowDescription() -> String {
        for window in NSApp.windows {
            let name = String(describing: type(of: window))
            if name.contains("Menu") {
                let size = window.frame.size
                return "\(name) size=\(Int(size.width))x\(Int(size.height)) visible=\(window.isVisible)"
            }
        }
        return "none"
    }

    // MARK: - The menu behind the icon

    /// Presses the button in the menu bar, so that its menu opens.
    private static func openMenuBarMenu() {
        for window in NSApp.windows {
            // The window that holds the menu bar item is an `NSStatusBarWindow`,
            // which AppKit does not publish under that name.
            guard String(describing: type(of: window)) == "NSStatusBarWindow",
                  let button = window.contentView else { continue }
            if let control = button as? NSControl {
                control.performClick(nil)
                return
            }
        }
    }

    /// What the menu behind the icon holds, as the system sees it.
    private static func menuReport() -> String {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var lines: [String] = []
        for window in NSApp.windows {
            let size = window.frame.size
            lines.append("window: class=\(type(of: window)) size=\(Int(size.width))x\(Int(size.height)) visible=\(window.isVisible)")
        }
        var seen = 0
        collectMenus(app, depth: 0, into: &lines, found: &seen)
        guard seen > 0 else { return lines.joined(separator: "\n") + "\nmenu: nothing found\n" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func collectMenus(_ element: AXUIElement, depth: Int, into lines: inout [String], found: inout Int) {
        guard depth < 8 else { return }
        for child in axChildren(element) {
            let role = axString(child, kAXRoleAttribute)
            if role == "AXMenu" {
                found += 1
                lines.append("menu:")
                for item in axChildren(child) {
                    let itemRole = axString(item, kAXRoleAttribute)
                    let title = axString(item, kAXTitleAttribute)
                    let value = axString(item, kAXValueAttribute)
                    let frame = axFrame(item)
                    lines.append(String(format: "  %@ \"%@\" value=\"%@\" frame=(%.0f,%.0f,%.0f,%.0f)",
                                        itemRole, title, value,
                                        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height))
                }
            }
            collectMenus(child, depth: depth + 1, into: &lines, found: &found)
        }
    }

    // MARK: - Snapshot

    /// Writes a picture of the settings window.
    private static func writeSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 300 }),
              let view = window.contentView else { return }

        write(view, to: path)

        // The sidebar is a column of its own inside the split view, so it is
        // captured on its own as well.
        if let column = columnView(in: view) {
            write(column, to: path.replacingOccurrences(of: ".png", with: "-sidebar.png"))
        }
    }

    private static func write(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// The narrow column on the left — the sidebar.
    private static func columnView(in view: NSView) -> NSView? {
        for subview in view.subviews {
            let frame = subview.convert(subview.bounds, to: view)
            if frame.minX < 4, frame.width > 100, frame.width < 320, frame.height > 200 {
                return subview
            }
            if let found = columnView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Accessibility

    /// A dump of what the window holds, as the system sees it.
    ///
    /// It is the honest way to check that a window is complete: every control
    /// that is on screen is listed with the place it sits in.
    private static func accessibilityReport() -> String {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

        var windows: [AXUIElement] = []
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success {
            windows = value as? [AXUIElement] ?? []
        }

        var lines: [String] = []
        for window in windows {
            let title = axString(window, kAXTitleAttribute)
            guard !title.isEmpty else { continue }
            lines.append("ax-window: \(title)")
            walk(window, depth: 1, into: &lines)
        }
        return lines.isEmpty ? "ax: nothing\n" : lines.joined(separator: "\n") + "\n"
    }

    /// Every element of the tree, with the number of children it has.
    private static func outlineReport() -> String {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var windows: [AXUIElement] = []
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success {
            windows = value as? [AXUIElement] ?? []
        }
        var lines: [String] = []
        for window in windows {
            let title = axString(window, kAXTitleAttribute)
            guard !title.isEmpty else { continue }
            lines.append("outline-window: \(title)")
            outline(window, depth: 1, into: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func outline(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 10 else { return }
        for child in axChildren(element) {
            let role = axString(child, kAXRoleAttribute)
            let title = axString(child, kAXTitleAttribute)
            let label = axString(child, kAXDescriptionAttribute)
            let frame = axFrame(child)
            lines.append(String(format: "%@%@ \"%@ %@\" children=%d frame=(%.0f,%.0f,%.0f,%.0f)",
                                String(repeating: "  ", count: depth),
                                role, title, label,
                                axChildren(child).count,
                                frame.origin.x, frame.origin.y, frame.size.width, frame.size.height))
            outline(child, depth: depth + 1, into: &lines)
        }
    }

    private static func walk(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 12 else { return }
        for child in axChildren(element) {
            let role = axString(child, kAXRoleAttribute)
            let title = axString(child, kAXTitleAttribute)
            let label = axString(child, kAXDescriptionAttribute)
            let value = axString(child, kAXValueAttribute)
            let frame = axFrame(child)
            let text = [title, label].filter { !$0.isEmpty }.joined(separator: " | ")
            if !text.isEmpty || role == "AXButton" || role == "AXCheckBox" || role == "AXRadioButton" {
                lines.append(String(format: "%@%@ \"%@\" value=\"%@\" frame=(%.0f,%.0f,%.0f,%.0f)",
                                    String(repeating: "  ", count: depth),
                                    role, text, value,
                                    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height))
            }
            walk(child, depth: depth + 1, into: &lines)
        }
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero

        var position: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
           CFGetTypeID(position) == AXValueGetTypeID() {
            AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        }
        var extent: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &extent) == .success,
           CFGetTypeID(extent) == AXValueGetTypeID() {
            AXValueGetValue(extent as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}
