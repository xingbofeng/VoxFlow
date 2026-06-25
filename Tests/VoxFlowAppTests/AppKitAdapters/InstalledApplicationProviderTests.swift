import XCTest
@testable import VoxFlowApp

final class InstalledApplicationProviderTests: XCTestCase {
    private var tempDir: URL!
    private var fm: FileManager!

    override func setUp() {
        super.setUp()
        fm = FileManager()
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("IAPTests-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: tempDir)
        super.tearDown()
    }

    func testScansUserApplicationsDirectory() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: applications.appendingPathComponent("FakeApp.app", isDirectory: true),
            bundleID: "com.fake.app",
            name: "FakeApp"
        )
        let home = tempDir.appendingPathComponent("Home", isDirectory: true)
        let userApps = home.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: userApps.appendingPathComponent("UserApp.app", isDirectory: true),
            bundleID: "com.user.app",
            name: "UserApp"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path,
            userHomePath: home.path
        )
        let apps = provider.scanInstalledApplications()

        let bundleIDs = Set(apps.map(\.bundleID))
        XCTAssertTrue(bundleIDs.contains("com.fake.app"))
        XCTAssertTrue(bundleIDs.contains("com.user.app"))
    }

    func testScansSystemApplicationsDirectory() throws {
        let systemApps = tempDir.appendingPathComponent("System/Applications", isDirectory: true)
        try createFakeAppBundle(
            at: systemApps.appendingPathComponent("SystemApp.app", isDirectory: true),
            bundleID: "com.system.app",
            name: "SystemApp"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        XCTAssertTrue(apps.contains { $0.bundleID == "com.system.app" })
    }

    func testScansCoreServicesApplicationsDirectory() throws {
        let coreServicesApps = tempDir
            .appendingPathComponent("System/Library/CoreServices/Applications", isDirectory: true)
        try createFakeAppBundle(
            at: coreServicesApps.appendingPathComponent("Archive Utility.app", isDirectory: true),
            bundleID: "com.apple.archiveutility",
            name: "Archive Utility"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        let app = apps.first { $0.bundleID == "com.apple.archiveutility" }
        XCTAssertEqual(app?.name, "Archive Utility")
        XCTAssertEqual(app?.systemCategory, .systemApplication)
    }

    func testScansSymbolicLinkedAppBundles() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        let linkedTarget = tempDir.appendingPathComponent("LinkedTargets/RealApp.app", isDirectory: true)
        try createFakeAppBundle(
            at: linkedTarget,
            bundleID: "com.linked.real",
            name: "Real App"
        )
        try fm.createDirectory(at: applications, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: applications.appendingPathComponent("LinkedApp.app", isDirectory: true),
            withDestinationURL: linkedTarget
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        XCTAssertEqual(apps.first { $0.bundleID == "com.linked.real" }?.name, "Real App")
    }

    func testDeduplicatesByBundleID() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: applications.appendingPathComponent("App1.app", isDirectory: true),
            bundleID: "com.duplicate.app",
            name: "App1"
        )
        let systemApps = tempDir.appendingPathComponent("System/Applications", isDirectory: true)
        try createFakeAppBundle(
            at: systemApps.appendingPathComponent("App2.app", isDirectory: true),
            bundleID: "com.duplicate.app",
            name: "App2"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        let matching = apps.filter { $0.bundleID == "com.duplicate.app" }
        XCTAssertEqual(matching.count, 1)
    }

    func testPrefersUserOverSystemForSameBundleID() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: applications.appendingPathComponent("UserVersion.app", isDirectory: true),
            bundleID: "com.shared.app",
            name: "UserVersion"
        )
        let systemApps = tempDir.appendingPathComponent("System/Applications", isDirectory: true)
        try createFakeAppBundle(
            at: systemApps.appendingPathComponent("SystemVersion.app", isDirectory: true),
            bundleID: "com.shared.app",
            name: "SystemVersion"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        let match = apps.first { $0.bundleID == "com.shared.app" }
        XCTAssertEqual(match?.name, "UserVersion")
        XCTAssertEqual(match?.systemCategory, .userApplication)
    }

    func testAppWithoutBundleIDGetsPathBasedID() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        let appURL = applications.appendingPathComponent("NoBundleID.app", isDirectory: true)
        try createFakeAppBundle(at: appURL, bundleID: nil, name: "NoBundleID")

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        let app = apps.first { $0.name == "NoBundleID" }
        XCTAssertNotNil(app)
        XCTAssertNil(app?.bundleID)
        XCTAssertTrue(app?.id.starts(with: "path:") == true)
    }

    func testDoesNotReadUserDocuments() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: applications.appendingPathComponent("RealApp.app", isDirectory: true),
            bundleID: "com.real.app",
            name: "RealApp"
        )
        // Create a Documents-like directory at the same level — scanner should ignore it
        let documents = tempDir.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try createFakeAppBundle(
            at: documents.appendingPathComponent("NotAnApp.app", isDirectory: true),
            bundleID: "com.not.an.app",
            name: "NotAnApp"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.bundleID, "com.real.app")
    }

    func testExtractsNameFromInfoPlist() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: applications.appendingPathComponent("SomeDir.app", isDirectory: true),
            bundleID: "com.named.app",
            name: "Custom Name From Plist"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        XCTAssertEqual(apps.first?.name, "Custom Name From Plist")
    }

    func testPrefersLocalizedInfoPlistDisplayName() throws {
        let applications = tempDir.appendingPathComponent("Applications", isDirectory: true)
        try createFakeAppBundle(
            at: applications.appendingPathComponent("Localized.app", isDirectory: true),
            bundleID: "com.localized.app",
            name: "English Name",
            localizedDisplayName: "本地化名称"
        )

        let provider = FileSystemInstalledApplicationProvider(
            fileManager: fm,
            applicationsRootPath: tempDir.path
        )
        let apps = provider.scanInstalledApplications()

        XCTAssertEqual(apps.first?.name, "本地化名称")
    }

    // MARK: - Helpers

    private func createFakeAppBundle(
        at url: URL,
        bundleID: String?,
        name: String,
        localizedDisplayName: String? = nil
    ) throws {
        let contentsURL = url.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var plist: [String: Any] = ["CFBundleName": name]
        if let bundleID {
            plist["CFBundleIdentifier"] = bundleID
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        fm.createFile(
            atPath: contentsURL.appendingPathComponent("Info.plist").path,
            contents: data
        )
        if let localizedDisplayName {
            let localizationURL = resourcesURL.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
            try fm.createDirectory(at: localizationURL, withIntermediateDirectories: true)
            let strings = "\"CFBundleDisplayName\" = \"\(localizedDisplayName)\";\n"
            fm.createFile(
                atPath: localizationURL.appendingPathComponent("InfoPlist.strings").path,
                contents: Data(strings.utf8)
            )
        }
    }
}
