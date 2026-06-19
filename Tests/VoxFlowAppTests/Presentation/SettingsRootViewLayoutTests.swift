import XCTest
@testable import VoxFlowApp

final class SettingsRootViewLayoutTests: XCTestCase {
    func testGeneralPreferencesUseSingleInputLanguageGroupCard() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var inputLanguageCard"))
        XCTAssertTrue(source.contains("title: \"输入与语言\""))
        XCTAssertTrue(source.contains("inputDeviceRow"))
        XCTAssertTrue(source.contains("recognitionLanguageRow"))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 12) {\n                inputDeviceRow\n                recognitionLanguageRow\n            }"))
        XCTAssertTrue(source.contains("inputLanguageCard"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains("private var inputDeviceRow"))
        XCTAssertTrue(source.contains("private var recognitionLanguageRow"))
        XCTAssertTrue(source.contains(".menuStyle(.borderlessButton)\n        .frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertFalse(source.contains("private var topPreferenceCards"))
        XCTAssertFalse(source.contains("topPreferenceCardWidth"))
        XCTAssertFalse(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(source.contains("GridItem(.adaptive(minimum: 320)"))
    }

    func testModelSettingsAreSplitIntoDictationAndCorrectionSections() throws {
        let sourceURL = try Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/SettingsRootView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settingsSidebarButton(.dictationModels)"))
        XCTAssertTrue(source.contains("settingsSidebarButton(.correctionModels)"))
        XCTAssertTrue(source.contains("private var dictationModelsSection"))
        XCTAssertTrue(source.contains("private var correctionModelsSection"))
        XCTAssertTrue(source.contains("ASRProviderView(viewModel: asrProviderViewModel, embedded: true)"))
        XCTAssertTrue(source.contains("LLMProviderView(viewModel: llmProviderViewModel, embedded: true)"))
        XCTAssertFalse(source.contains("settingsSidebarButton(.models)"))
        XCTAssertFalse(source.contains("private var modelsSection"))
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "SettingsRootViewLayoutTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift from test file path."]
        )
    }
}
