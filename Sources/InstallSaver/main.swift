import AppKit

// Xcode's Run action for the MatrixRain scheme: reinstall the freshly built saver and open its settings.

let saverName = "MatrixRain.saver"
let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!

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

/// legacyScreenSaver keeps the old binary loaded until it exits; macOS relaunches it on demand.
func stopScreenSaverHosts() {
    step("Stopping legacyScreenSaver hosts")
    let pkill = Process()
    pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    pkill.arguments = ["-f", "legacyScreenSaver.appex/"]
    try? pkill.run()
    pkill.waitUntilExit()
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
step("Opening Screen Saver settings")
NSWorkspace.shared.open(settingsURL)
