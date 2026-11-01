import SwiftUI
import AutoTypeCore

/// The parts AutoType is divided into, one per row in the sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case dictionary
    case translation
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .dictionary: return "Dictionary"
        case .translation: return "AI Actions & Translation"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .dictionary: return "text.book.closed"
        case .translation: return "sparkles"
        case .about: return "info.circle"
        }
    }
}

/// The settings window.
///
/// The settings used to be stacked in one narrow column, which made every
/// part of them feel crowded. They are split the way macOS splits its own
/// settings: a sidebar that names the parts of AutoType, and a detail pane
/// that holds the settings of the selected part.
struct SettingsView: View {

    @EnvironmentObject private var model: SettingsModel
    @State private var selection: SettingsSection?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            model.reload()
            model.refreshInputSourceStatus()
            if selection == nil {
                // A check can ask for one part of the window, so that the
                // layout of every part can be looked at.
                selection = AppRouter.shared.pendingSection ?? .general
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        let section = selection ?? .general
        VStack(spacing: 0) {
            PaneTitle(text: section.title)
            switch section {
            case .general:
                GeneralSettingsView()
            case .dictionary:
                DictionarySettingsView()
            case .translation:
                TranslationSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
    }
}
