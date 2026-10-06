import XCTest

final class SaverInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SaverInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundle(named name: String, in directory: URL, marker: String) throws -> URL {
        let bundle = directory.appendingPathComponent(name)
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: contents.appendingPathComponent(marker))
        return bundle
    }

    func testInstallsIntoMissingDirectory() throws {
        let source = try makeBundle(named: "MatrixRain.saver", in: root.appendingPathComponent("build"), marker: "new")
        let savers = root.appendingPathComponent("Screen Savers")
        let installed = try SaverInstaller(source: source, destinationDirectory: savers).install()
        XCTAssertEqual(installed.lastPathComponent, "MatrixRain.saver")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/new").path))
    }

    func testReplacesOldInstallCompletely() throws {
        let savers = root.appendingPathComponent("Screen Savers")
        _ = try makeBundle(named: "MatrixRain.saver", in: savers, marker: "old")
        let source = try makeBundle(named: "MatrixRain.saver", in: root.appendingPathComponent("build"), marker: "new")
        let installed = try SaverInstaller(source: source, destinationDirectory: savers).install()
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/new").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/old").path),
                       "files from the old build must not survive")
    }

    func testMissingBuildLeavesExistingInstallAlone() throws {
        let savers = root.appendingPathComponent("Screen Savers")
        let existing = try makeBundle(named: "MatrixRain.saver", in: savers, marker: "old")
        let missing = root.appendingPathComponent("build/MatrixRain.saver")
        XCTAssertThrowsError(try SaverInstaller(source: missing, destinationDirectory: savers).install())
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.appendingPathComponent("Contents/old").path))
    }
}
