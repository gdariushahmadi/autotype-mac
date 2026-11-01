import Foundation

/// Watches the folder that holds AutoType's shared configuration and reports
/// every change.
///
/// The settings app writes its file atomically, which replaces the file rather
/// than editing it, so the folder itself is watched rather than the file.
final class SettingsWatcher {

    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "digital.autotype.settings-watcher")
    private let onChange: () -> Void

    init(directory: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        start(directory: directory)
    }

    deinit {
        source?.cancel()
    }

    private func start(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.onChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }
}
