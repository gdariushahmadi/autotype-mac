import SwiftUI
import AppKit
import AutoTypeCore

/// Settings pane to manage applications where AutoType is completely disabled.
struct ExcludedAppsSettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var customBundleID = ""
    @State private var search = ""

    /// Popular preset applications that developers and users frequently exclude.
    private struct PresetApp: Identifiable {
        let name: String
        let bundleID: String
        let symbol: String

        var id: String { bundleID }
    }

    private let presets: [PresetApp] = [
        PresetApp(name: "Terminal", bundleID: "com.apple.Terminal", symbol: "terminal"),
        PresetApp(name: "iTerm2", bundleID: "com.googlecode.iterm2", symbol: "terminal.fill"),
        PresetApp(name: "VS Code", bundleID: "com.microsoft.VSCode", symbol: "chevron.left.forwardslash.chevron.right"),
        PresetApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", symbol: "cursorarrow.rays"),
        PresetApp(name: "Xcode", bundleID: "com.apple.dt.Xcode", symbol: "hammer.fill"),
        PresetApp(name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij", symbol: "laptopcomputer"),
    ]

    private var filteredApps: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return model.settings.disabledApps
        }
        return model.settings.disabledApps.filter { bundleID in
            bundleID.lowercased().contains(query) || appDisplayName(for: bundleID).lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Explanation Header Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge.xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bypass AutoType in Specific Apps")
                            .font(.headline)
                        Text("AutoType stands down in excluded apps, passing all keystrokes unmodified directly to macOS.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Quick Add Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Presets:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets) { preset in
                                let isExcluded = model.settings.isAppDisabled(bundleID: preset.bundleID)
                                Button {
                                    if isExcluded {
                                        model.removeDisabledApp(preset.bundleID)
                                    } else {
                                        model.addDisabledApp(preset.bundleID)
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: isExcluded ? "checkmark.circle.fill" : preset.symbol)
                                            .foregroundStyle(isExcluded ? .green : .primary)
                                        Text(preset.name)
                                    }
                                    .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(AutoTypeMetrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: AutoTypeMetrics.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AutoTypeMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .padding(.horizontal, AutoTypeMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Search and Add Actions
            HStack(spacing: 10) {
                SearchField(text: $search, placeholder: "Search excluded apps")

                Button {
                    chooseApplicationFile()
                } label: {
                    Label("Choose App…", systemImage: "plus.app")
                }
                .controlSize(.regular)
            }
            .padding(.horizontal, AutoTypeMetrics.gutter)
            .padding(.bottom, 10)

            // Manual bundle identifier input
            HStack(spacing: 8) {
                TextField("Add custom bundle identifier (e.g. com.example.app)", text: $customBundleID)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addCustomApp()
                    }

                Button("Add") {
                    addCustomApp()
                }
                .disabled(customBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, AutoTypeMetrics.gutter)
            .padding(.bottom, 12)

            // List of Excluded Apps
            if model.settings.disabledApps.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Applications Excluded")
                        .font(.headline)
                    Text("AutoType is active in all applications. Click a preset or \"Choose App…\" above to exclude coding or terminal apps.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredApps, id: \.self) { bundleID in
                        HStack(spacing: 12) {
                            appIconView(for: bundleID)
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appDisplayName(for: bundleID))
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            Button {
                                model.removeDisabledApp(bundleID)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from excluded list")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func addCustomApp() {
        let trimmed = customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.addDisabledApp(trimmed)
        customBundleID = ""
    }

    private func chooseApplicationFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"

        if panel.runModal() == .OK {
            for url in panel.urls {
                if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                    model.addDisabledApp(bundleID)
                }
            }
        }
    }

    private func appDisplayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            if !name.isEmpty && name != url.lastPathComponent {
                return name
            }
            return url.deletingPathExtension().lastPathComponent
        }
        // Fallback: extract meaningful name from bundle ID
        let components = bundleID.split(separator: ".")
        if let last = components.last {
            return String(last).capitalized
        }
        return bundleID
    }

    @ViewBuilder
    private func appIconView(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
