import Foundation

/// Append-only log in the App Group container.
///
/// This is the only debugger this project has. The build machine is a rented Mac in a
/// datacentre, so the phone is never attached to Xcode and `print` goes nowhere you can
/// read. Every line is flushed on write because the case worth capturing is the process
/// being suspended or killed without warning, and a buffered line is a lost line.
final class SpikeLog {
    static let shared = SpikeLog()

    /// True when the App Group container was unavailable and the log fell back to the
    /// app's own Documents directory. Surfaced in the UI rather than swallowed: it means
    /// the entitlement is misconfigured, and the widget would silently fail to share
    /// state for the same reason.
    private(set) var usingFallbackLocation = false

    let fileURL: URL

    private let queue = DispatchQueue(label: "nextstop.spikelog")
    private let stamp: ISO8601DateFormatter

    private init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        let resolved: URL
        var fallback = false
        if let container {
            resolved = container.appendingPathComponent("spike.log")
        } else {
            fallback = true
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            resolved = documents.appendingPathComponent("spike.log")
        }

        stamp = formatter
        fileURL = resolved
        usingFallbackLocation = fallback
    }

    func write(_ event: String, _ detail: String = "") {
        let line = "\(stamp.string(from: Date()))\t\(event)\t\(detail)\n"
        queue.async { [fileURL] in
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: data)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.synchronize()
        }
    }

    func read() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func clear() {
        queue.async { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    var sizeDescription: String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
