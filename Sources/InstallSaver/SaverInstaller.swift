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

    static let screenSaverSettingsID = "com.apple.ScreenSaver-Settings.extension"
    static let wallpaperSettingsID = "com.apple.Wallpaper-Settings.extension"

    /// The System Settings pane that lists screensavers. Newer macOS versions merged the Screen Saver
    /// pane into Wallpaper, where its link silently falls back to General.
    static func settingsURL(installedSettingsExtensions: Set<String>) -> URL {
        let pane = installedSettingsExtensions.contains(screenSaverSettingsID) ? screenSaverSettingsID : wallpaperSettingsID
        return URL(string: "x-apple.systempreferences:\(pane)")!
    }

    /// Bundle identifiers of the System Settings panes installed on this Mac.
    static func installedSettingsExtensions() -> Set<String> {
        let directory = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
        let bundles = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return Set(bundles.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

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
