import Foundation

/// TfNSW stop names carry boarding suffixes — "Artarmon Station, Platform 2",
/// "Chatswood Interchange, Stand B", "Circular Quay, Wharf 4". The suffix is signal at
/// the stop you board or leave from and noise everywhere else, so it splits rather
/// than deletes.
enum StopName {
    /// "Artarmon Station, Platform 2" → "Artarmon Station". Unrecognised names pass
    /// through untouched, as does a name that is only a suffix ("Platform 2").
    static func short(_ raw: String) -> String {
        split(raw).short
    }

    /// The suffix alone — "Platform 2" / "Stand B" / "Wharf 4" — else nil.
    static func platform(_ raw: String) -> String? {
        split(raw).platform
    }

    private static func split(_ raw: String) -> (short: String, platform: String?) {
        guard let comma = raw.range(of: ", ", options: .backwards) else { return (raw, nil) }
        let leading = String(raw[..<comma.lowerBound])
        let trailing = String(raw[comma.upperBound...])
        guard !leading.isEmpty,
              trailing.range(
                  of: #"^(Platform|Stand|Wharf)\b.+"#,
                  options: [.regularExpression, .caseInsensitive]
              ) != nil
        else { return (raw, nil) }
        return (leading, trailing)
    }
}
