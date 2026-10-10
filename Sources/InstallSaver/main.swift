import AppKit

// Xcode's Run action for the MatrixRain scheme: reinstall the freshly built saver and open its settings.

let saverName = "MatrixRain.saver"
let settingsURL = SaverInstaller.settingsURL(installedSettingsExtensions: SaverInstaller.installedSettingsExtensions())

func step(_ message: String) { print("▸ \(message)") }

func quitSystemSettings() {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
    guard !apps.isEmpty else { return }
    step("Quitting System Settings")
    apps.forEach { $0.terminate() }
    let deadline = Date().addingTimeInterval(5)
    while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
}

func stop(processesMatching pattern: String) {
    let pkill = Process()
    pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    pkill.arguments = ["-f", pattern]
    try? pkill.run()
    pkill.waitUntilExit()
}

/// legacyScreenSaver keeps the old binary loaded until it exits, and WallpaperLegacyExtension caches
/// each saver's thumbnail; macOS relaunches both on demand.
func stopScreenSaverHosts() {
    step("Stopping legacyScreenSaver hosts and the screensaver thumbnail cache")
    stop(processesMatching: "legacyScreenSaver.appex/")
    stop(processesMatching: "WallpaperLegacyExtension.appex/")
}

let buildDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
    ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let installer = SaverInstaller(
    source: buildDirectory.appendingPathComponent(saverName),
    destinationDirectory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers")
)

quitSystemSettings()
stopScreenSaverHosts()
do {
    let installed = try installer.install()
    step("Installed \(installed.path)")
} catch {
    print("✗ Install failed: \(error)")
    exit(1)
}
step("Opening \(settingsURL.absoluteString)")
NSWorkspace.shared.open(settingsURL)
