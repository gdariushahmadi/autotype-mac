import SwiftUI
import AppKit

// MARK: - Metrics

/// The measurements the settings window is built from.
///
/// The numbers follow the rhythm macOS uses in its own grouped settings: a
/// card is inset by 14 points, its corners are rounded by 10, and the groups
/// themselves are separated by the 20 point window margin.
enum AutoTypeMetrics {
    static let cardRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let gutter: CGFloat = 16
    /// The margin macOS keeps between the edge of a settings pane and its
    /// content.
    static let windowMargin: CGFloat = 20
}

// MARK: - Card

/// A rounded container with a hairline border.
///
/// Everything that is not a control — the status of the input method, the
/// descriptions — sits in one of these, so the window has a
/// single surface instead of a mixture of panels.
struct Card<Content: View>: View {

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(AutoTypeMetrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: AutoTypeMetrics.cardRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AutoTypeMetrics.cardRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

// MARK: - Help text

/// The small grey sentence that explains a control.
struct InlineHelp: View {

    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pane title

/// The name of the part of AutoType that is open, in the big type macOS
/// gives to the title of a settings pane.
struct PaneTitle: View {

    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AutoTypeMetrics.windowMargin)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

// MARK: - Count badge

/// The number of entries in a list, next to its title.
struct CountBadge: View {

    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - App icon

/// The app icon, taken from the bundle.
struct AppIconView: View {

    private let size: CGFloat

    init(size: CGFloat = 28) {
        self.size = size
    }

    var body: some View {
        Group {
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "character.book.closed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.18)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Search field

/// A search field shaped the way macOS shapes them: a plain text field with
/// a magnifier in front of it and a clear button behind it.
struct SearchField: View {

    @Binding var text: String
    var placeholder: String = "Search"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
