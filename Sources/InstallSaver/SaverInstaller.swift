import Foundation

/// Replaces an installed screensaver bundle with a freshly built one.
/// The old bundle is removed first so no files from a previous build survive.
struct SaverInstaller {
    enum Failure: Error, CustomStringConvertible {
        case missingBuild(URL)

        var description: String {
            switch self {
            case .missingBuild(let url): "No built screensaver at \(url.path)"
            }
        }
    }

    let source: URL
    let destinationDirectory: URL

    var destination: URL { destinationDirectory.appendingPathComponent(source.lastPathComponent) }

    @discardableResult
    func install(fileManager: FileManager = .default) throws -> URL {
        guard fileManager.fileExists(atPath: source.path) else { throw Failure.missingBuild(source) }
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
