import Foundation

/// Locates the dictionary resources that ship with AutoType.
public enum AutoTypeResources {

    public enum ResourceError: Error, LocalizedError {
        case missingResource(String)
        case unreadableResource(String, Error)

        public var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "AutoType could not find its dictionary resource “\(name)”."
            case .unreadableResource(let name, let error):
                return "AutoType could not read “\(name)”: \(error.localizedDescription)"
            }
        }
    }

    /// The bundle that holds the dictionary files, when it can be opened as a
    /// real bundle.
    ///
    /// SwiftPM emits a *flat* resource bundle on macOS — the files sit at the
    /// top of `AutoType_AutoTypeCore.bundle` rather than inside
    /// `Contents/Resources` — and such a directory is not always a bundle that
    /// `Bundle(url:)` will open. The files are therefore looked up by path as
    /// well, so a packaged app never depends on the bundle structure.
    public static let bundle: Bundle? = {
        for directory in searchDirectories {
            for name in bundleNames {
                let candidate = directory.appendingPathComponent(name)
                if let bundle = Bundle(url: candidate) { return bundle }
            }
        }
        return nil
    }()

    private static let bundleNames = [
        "AutoType_AutoTypeCore.bundle",
        "AutoTypeCore_AutoTypeCore.bundle",
    ]

    /// Every place a dictionary file may live.
    private static var searchDirectories: [URL] {
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL { directories.append(resources) }
        directories.append(Bundle.main.bundleURL)
        if let executable = Bundle.main.executableURL {
            let folder = executable.deletingLastPathComponent()
            directories.append(folder)
            directories.append(folder.appendingPathComponent("Resources"))
        }
        // The SwiftPM build products directory, used when running from source.
        if let buildRoot = ProcessInfo.processInfo.environment["AUTOTYPE_BUILD_DIR"] {
            directories.append(URL(fileURLWithPath: buildRoot))
        }
        return directories
    }

    /// Loads the Persian and English word lists.
    public static func loadLexicon() throws -> Lexicon {
        let persian = try url(for: "persian-lexicon.tsv")
        let english = try url(for: "english-lexicon.txt")
        let englishCommon = try url(for: "english-common.txt")
        do {
            return try Lexicon(persianURL: persian, englishURL: english, englishCommonURL: englishCommon)
        } catch {
            throw ResourceError.unreadableResource("persian-lexicon.tsv", error)
        }
    }

    private static func url(for name: String) throws -> URL {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: nil) {
            return url
        }
        #endif

        if let bundle, let url = bundle.url(forResource: name, withExtension: nil) {
            return url
        }

        for directory in searchDirectories {
            var candidates = [directory.appendingPathComponent(name)]
            for bundleName in bundleNames {
                let root = directory.appendingPathComponent(bundleName)
                candidates.append(root.appendingPathComponent(name))
                candidates.append(root.appendingPathComponent("Contents/Resources/\(name)"))
            }
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw ResourceError.missingResource(name)
    }
}
