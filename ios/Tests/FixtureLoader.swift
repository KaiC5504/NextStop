import Foundation

enum Fixture {
    /// A resource missing from the test bundle is a project-generation fault, not a test
    /// failure worth recovering from — fail loudly with the name that was not found.
    static func data(_ name: String) -> Data {
        guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json") else {
            fatalError("fixture \(name).json is not in the test bundle")
        }
        return try! Data(contentsOf: url)
    }
}

private final class BundleToken {}
