import Foundation
import CoreServices

/// Watches a directory tree (recursively) via FSEvents and fires `onChange`
/// when files are added, removed, or renamed outside the IDE. The callback
/// is delivered on a private queue — hop to the main actor before touching
/// UI state, and debounce, since bursts of events are common.
final class FileSystemWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "MSP430IDE.fswatch")
    private let path: String
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        // passRetained keeps self alive for the lifetime of the stream.
        // The paired release in the context releases it when the stream is torn down.
        let retained = Unmanaged.passRetained(self)
        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<FileSystemWatcher>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4, // latency: coalesce rapid bursts
            flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
