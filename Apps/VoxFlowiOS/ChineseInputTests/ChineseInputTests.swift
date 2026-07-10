import XCTest
@testable import ChineseInput

@MainActor
final class ChineseInputTests: XCTestCase {
    private static let nativeRimeRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MashangxieNativeRimeBridgeTests", isDirectory: true)

    func testChineseInputSessionUpdatesPreeditAndCandidates() async throws {
        let expected = ChineseCompositionState(
            preedit: "ni",
            candidates: [
                CandidateSuggestion(
                    index: 23,
                    label: "24",
                    text: "你",
                    title: "你",
                    isAutocomplete: true,
                    subtitle: "ni"
                ),
                CandidateSuggestion(index: 1, label: "2", text: "尼"),
            ]
        )
        let bridge = FakeChineseRimeBridge(
            states: [
                expected,
            ]
        )
        let session = ChineseInputSession(bridge: bridge)

        let action = try await session.input("ni")

        XCTAssertEqual(action, .updateComposition(expected))
        XCTAssertEqual(session.state.composition.preedit, "ni")
        XCTAssertEqual(session.state.composition.candidates.map(\.text), ["你", "尼"])
        XCTAssertEqual(session.state.composition.candidates.first?.index, 23)
        XCTAssertEqual(session.state.composition.candidates.first?.label, "24")
        XCTAssertEqual(session.state.composition.candidates.first?.title, "你")
        XCTAssertEqual(session.state.composition.candidates.first?.subtitle, "ni")
        XCTAssertEqual(session.state.composition.candidates.first?.isAutocomplete, true)
    }

    func testChineseInputSessionLoadMoreAppendsCandidatesAndPreservesIndexes() async throws {
        let firstPage = (0..<20).map {
            CandidateSuggestion(index: $0, label: "\($0 + 1)", text: "候选\($0)")
        }
        let secondPage = (20..<40).map {
            CandidateSuggestion(index: $0, label: "\($0 + 1)", text: "候选\($0)")
        }
        let bridge = FakeChineseRimeBridge(
            initial: .init(preedit: "shi", candidates: firstPage, hasMoreCandidates: true),
            additionalCandidatePages: [secondPage]
        )
        let session = ChineseInputSession(bridge: bridge)

        try await session.start(hasFullAccess: false)
        let action = try await session.loadMoreCandidates()

        guard case let .updateComposition(composition) = action else {
            XCTFail("Expected updated composition after loading more candidates")
            return
        }
        XCTAssertEqual(composition.candidates.count, 40)
        XCTAssertEqual(composition.candidates.map(\.index), Array(0..<40))
        XCTAssertEqual(bridge.requestedCandidateLimits, [20])
        XCTAssertTrue(composition.hasMoreCandidates)
    }

    func testChineseInputSessionCandidateLoadingStopsAtOneHundred() async throws {
        let firstPage = (0..<95).map {
            CandidateSuggestion(index: $0, label: "\($0 + 1)", text: "候选\($0)")
        }
        let finalPage = (95..<100).map {
            CandidateSuggestion(index: $0, label: "\($0 + 1)", text: "候选\($0)")
        }
        let bridge = FakeChineseRimeBridge(
            initial: .init(preedit: "shi", candidates: firstPage, hasMoreCandidates: true),
            additionalCandidatePages: [finalPage]
        )
        let session = ChineseInputSession(bridge: bridge)

        try await session.start(hasFullAccess: false)
        _ = try await session.loadMoreCandidates()
        let secondAction = try await session.loadMoreCandidates()

        XCTAssertEqual(session.state.composition.candidates.count, 100)
        XCTAssertFalse(session.state.composition.hasMoreCandidates)
        XCTAssertEqual(bridge.requestedCandidateLimits, [5])
        XCTAssertEqual(secondAction, .updateComposition(session.state.composition))
    }

    func testChineseInputSessionSelectsPinyinCandidateThroughBridge() async throws {
        let initial = ChineseCompositionState(
            preedit: "94664",
            candidates: [CandidateSuggestion(index: 0, label: "1", text: "熊")],
            pinyinCandidates: ["xiong", "zhong"],
            selectedPinyin: nil
        )
        let selected = ChineseCompositionState(
            preedit: "zhong",
            candidates: [CandidateSuggestion(index: 0, label: "1", text: "中")],
            pinyinCandidates: ["xiong", "zhong"],
            selectedPinyin: "zhong"
        )
        let bridge = FakeChineseRimeBridge(
            initial: initial,
            selectedPinyinStates: [selected]
        )
        let session = ChineseInputSession(mode: .chineseNineGrid, bridge: bridge)

        try await session.start(hasFullAccess: false)
        let action = try await session.selectPinyinCandidate("zhong")

        XCTAssertEqual(bridge.selectedPinyinCandidates, ["zhong"])
        XCTAssertEqual(action, .updateComposition(selected))
        XCTAssertEqual(session.state.composition.selectedPinyin, "zhong")
        XCTAssertEqual(session.state.composition.candidates.first?.text, "中")
    }

    func testChineseInputSessionReportsStartedOnlyAfterBridgeStarts() async throws {
        let bridge = FakeChineseRimeBridge()
        let session = ChineseInputSession(bridge: bridge)

        XCTAssertFalse(session.isStarted)

        try await session.start(hasFullAccess: false)

        XCTAssertTrue(session.isStarted)
    }

    func testChineseInputSessionCommitsSelectedCandidateAndClearsComposition() async throws {
        let bridge = FakeChineseRimeBridge(
            initial: .init(
                preedit: "ni",
                candidates: [
                    CandidateSuggestion(index: 0, label: "1", text: "你"),
                    CandidateSuggestion(index: 1, label: "2", text: "泥"),
                ]
            ),
            selected: [
                .init(commitText: "泥"),
            ]
        )
        let session = ChineseInputSession(bridge: bridge)

        _ = try await session.input("ni")
        let action = try await session.selectCandidate(at: 1)

        XCTAssertEqual(action, .commitText("泥"))
        XCTAssertFalse(session.state.hasActiveComposition)
        XCTAssertEqual(bridge.selectedIndexes, [1])
    }

    func testChineseInputSessionDeletesCompositionBeforeHostText() async throws {
        let bridge = FakeChineseRimeBridge(
            initial: .init(preedit: "ni", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")]),
            deleted: [
                .init(preedit: "n", candidates: []),
                .init(),
            ]
        )
        let session = ChineseInputSession(bridge: bridge)

        _ = try await session.input("ni")
        let firstDelete = try await session.deleteBackward()
        let secondDelete = try await session.deleteBackward()
        let thirdDelete = try await session.deleteBackward()

        XCTAssertEqual(firstDelete, .updateComposition(.init(preedit: "n", candidates: [])))
        XCTAssertEqual(secondDelete, .updateComposition(.init()))
        XCTAssertEqual(thirdDelete, .deleteHostText)
    }

    func testChineseInputSessionPrepareForVoiceCommitsFirstCandidateByDefault() async throws {
        let bridge = FakeChineseRimeBridge(
            initial: .init(
                preedit: "zhong",
                candidates: [CandidateSuggestion(index: 0, label: "1", text: "中")]
            )
        )
        let session = ChineseInputSession(bridge: bridge)

        _ = try await session.input("zhong")
        let action = await session.prepareForVoice()

        XCTAssertEqual(action, .commitText("中"))
        XCTAssertFalse(session.state.hasActiveComposition)
        XCTAssertEqual(bridge.resetCallCount, 1)
    }

    func testChineseInputSessionCommitsPreeditWhenNoCandidatesExist() async throws {
        let bridge = FakeChineseRimeBridge(
            initial: .init(preedit: "wo", candidates: [])
        )
        let session = ChineseInputSession(bridge: bridge)

        _ = try await session.input("wo")
        let action = await session.commitBestCandidateOrPreedit()

        XCTAssertEqual(action, .commitText("wo"))
        XCTAssertFalse(session.state.hasActiveComposition)
        XCTAssertEqual(bridge.resetCallCount, 1)
    }

    func testChineseInputSessionClearsCompositionWhenLeavingChineseMode() async throws {
        let bridge = FakeChineseRimeBridge(
            initial: .init(preedit: "ni", candidates: [CandidateSuggestion(index: 0, label: "1", text: "你")])
        )
        let session = ChineseInputSession(bridge: bridge)

        _ = try await session.input("ni")
        let action = try await session.switchMode(.english)

        XCTAssertEqual(action, .updateComposition(.init()))
        XCTAssertEqual(session.state.mode, .english)
        XCTAssertFalse(session.state.hasActiveComposition)
        XCTAssertEqual(bridge.resetCallCount, 1)
    }

    func testHamsterT9ExamplesAreAvailable() {
        XCTAssertEqual(HamsterT9.pinyinCandidates(for: "64"), ["mi", "ni"])
        XCTAssertEqual(HamsterT9.pinyinCandidates(for: "646"), ["min", "nin"])
        XCTAssertEqual(HamsterT9.pinyinCandidates(for: "6464"), ["ming", "ning"])
        XCTAssertEqual(HamsterT9.pinyinCandidates(for: "94664"), ["xiong", "zhong"])
    }

    func testHamsterT9PinyinToDigitMapping() {
        XCTAssertEqual(HamsterT9.digitSequence(forPinyin: "zhong"), "94664")
        XCTAssertEqual(HamsterT9.digitSequence(forPinyin: "ming"), "6464")
        XCTAssertEqual(HamsterT9.restorePreview("94664", candidateComment: "zhong"), "zhong")
    }

    func testChineseNineGridLayoutMatchesHamsterRows() {
        let labels = ChineseNineGridLayout.rows.map { row in row.map(\.displayLabel) }
        XCTAssertEqual(labels[0], ["symbols", "ABC", "DEF", "delete"])
        XCTAssertEqual(labels[1], ["GHI", "JKL", "MNO", "return"])
        XCTAssertEqual(labels[2], ["PQRS", "TUV", "WXYZ", "emoji"])
        XCTAssertEqual(labels[3], ["123", "space", "switchLanguage", "send"])
        XCTAssertEqual(ChineseNineGridLayout.rows[2][2].inputDigit, "9")
    }

    func testBuiltInSchemaDeploymentPlanReportsCompletenessAndDirectories() throws {
        let root = Self.nativeRimeRoot
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        XCTAssertTrue(plan.canDeployBuiltInSchemas)
        XCTAssertEqual(plan.missingRequiredSchemaNames, [])

        try plan.createDirectories()
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.directories.appGroupSharedSupport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.directories.appGroupUserData.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.directories.sandboxSharedSupport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.directories.sandboxUserData.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.directories.futureImportedSchemas.path))
    }

    func testDeployBuiltInSchemasCopiesResourcesToSharedSupportDirectories() throws {
        let root = Self.nativeRimeRoot
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        try plan.deployBuiltInSchemas(from: try schemaResourceBundle())

        for name in RimeSchemaDeploymentPlan.requiredSchemaResourceNames {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: plan.directories.appGroupSharedSupport.appendingPathComponent(name).path
                ),
                name
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: plan.directories.sandboxSharedSupport.appendingPathComponent(name).path
                ),
                name
            )
        }

        for directoryName in ["cn_dicts", "en_dicts", "lua", "opencc"] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: plan.directories.appGroupSharedSupport.appendingPathComponent(directoryName).path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue,
                directoryName
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: plan.directories.sandboxSharedSupport.appendingPathComponent(directoryName).path,
                    isDirectory: &isDirectory
                ) && isDirectory.boolValue,
                directoryName
            )
        }

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: plan.directories.appGroupUserData
                    .appendingPathComponent("lua", isDirectory: true)
                    .appendingPathComponent("lunar.db")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: plan.directories.sandboxUserData
                    .appendingPathComponent("lua", isDirectory: true)
                    .appendingPathComponent("lunar.db")
                    .path
            )
        )
    }

    func testDeployBuiltInSchemasToSelectedDirectoryDoesNotCopyBothStorageRoots() throws {
        let root = Self.nativeRimeRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        try plan.deployBuiltInSchemas(
            from: try schemaResourceBundle(),
            sharedSupportDirectory: plan.directories.sandboxSharedSupport,
            userDataDirectory: plan.directories.sandboxUserData
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: plan.directories.sandboxSharedSupport.appendingPathComponent("rime_ice.dict.yaml").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: plan.directories.appGroupSharedSupport.path),
            "Sandbox/no-full-access startup should not pay the cost of an unused AppGroup deployment"
        )
    }

    func testDeployBuiltInSchemasCopiesPrebuiltBuildToUserDataOnly() throws {
        let root = Self.nativeRimeRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        try plan.deployBuiltInSchemas(
            from: try schemaResourceBundle(),
            sharedSupportDirectory: plan.directories.sandboxSharedSupport,
            userDataDirectory: plan.directories.sandboxUserData
        )

        for name in RimeSchemaDeploymentPlan.requiredPrebuiltBuildResourceNames {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: plan.directories.sandboxUserData
                        .appendingPathComponent("build", isDirectory: true)
                        .appendingPathComponent(name)
                        .path
                ),
                name
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: plan.directories.sandboxSharedSupport
                    .appendingPathComponent("build", isDirectory: true)
                    .appendingPathComponent("rime_ice.table.bin")
                    .path
            ),
            "Prebuilt Rime build artifacts belong in UserData/build, not SharedSupport/build"
        )
    }

    func testDeployBuiltInSchemasLinksLargePrebuiltBuildFilesToAvoidColdStartCopy() throws {
        let root = Self.nativeRimeRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        let bundle = try schemaResourceBundle()
        try plan.deployBuiltInSchemas(
            from: bundle,
            sharedSupportDirectory: plan.directories.sandboxSharedSupport,
            userDataDirectory: plan.directories.sandboxUserData
        )

        let table = plan.directories.sandboxUserData
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("rime_ice.table.bin")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: table.path)

        XCTAssertTrue(destination.hasSuffix("/Schemas/build/rime_ice.table.bin"), destination)
    }

    func testDeployBuiltInSchemasSkipsCurrentDeploymentWhenMarkerMatches() throws {
        let root = Self.nativeRimeRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )

        try plan.deployBuiltInSchemas(
            from: try schemaResourceBundle(),
            sharedSupportDirectory: plan.directories.sandboxSharedSupport,
            userDataDirectory: plan.directories.sandboxUserData
        )
        let sentinel = plan.directories.sandboxSharedSupport.appendingPathComponent("user-sentinel.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)

        try plan.deployBuiltInSchemas(
            from: try schemaResourceBundle(),
            sharedSupportDirectory: plan.directories.sandboxSharedSupport,
            userDataDirectory: plan.directories.sandboxUserData
        )

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testDeployBuiltInSchemasReplacesPreviouslyDeployedToyDictionariesWithRimeIce() throws {
        let root = Self.nativeRimeRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let plan = RimeSchemaDeploymentPlan(
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundledSchemaNames: RimeSchemaDeploymentPlan.requiredSchemaResourceNames
        )
        try plan.createDirectories()
        let staleFile = plan.directories.appGroupSharedSupport.appendingPathComponent("pinyin.dict.yaml")
        try "stale toy dictionary".write(to: staleFile, atomically: true, encoding: .utf8)

        try plan.deployBuiltInSchemas(from: try schemaResourceBundle())

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
        let rimeIceDictionary = plan.directories.appGroupSharedSupport.appendingPathComponent("rime_ice.dict.yaml")
        let deployed = try String(contentsOf: rimeIceDictionary, encoding: .utf8)
        XCTAssertTrue(deployed.contains("name: rime_ice"))
        XCTAssertFalse(deployed.contains("stale toy dictionary"))
    }

    func testBuiltInSchemaResourcesExistInBundle() {
        for name in RimeSchemaDeploymentPlan.requiredSchemaResourceNames {
            let resource = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            let found = (Bundle.allBundles + Bundle.allFrameworks).contains { bundle in
                bundle.url(forResource: resource, withExtension: ext, subdirectory: "Schemas") != nil
                    || bundle.url(forResource: resource, withExtension: ext) != nil
            }
            XCTAssertTrue(found, name)
        }
    }

    func testRimeNativeVendorFrameworksArePresentForIOSDevice() throws {
        let frameworksDirectory = try rimeFrameworksDirectory()

        XCTAssertEqual(
            try RimeNativeDependencyManifest.missingFrameworkNames(in: frameworksDirectory),
            []
        )

        for frameworkName in RimeNativeDependencyManifest.expectedFrameworkNames {
            let frameworkURL = frameworksDirectory
                .appendingPathComponent(frameworkName)
                .appendingPathExtension("xcframework")
            XCTAssertTrue(
                RimeNativeDependencyManifest.supportsIOSDeviceArm64(frameworkURL: frameworkURL),
                "\(frameworkName) must include an iOS arm64 device slice"
            )
        }
    }

    func testRimeNativeVendorSimulatorCoverageIsKnown() throws {
        let frameworksDirectory = try rimeFrameworksDirectory()
        let simulatorReady = RimeNativeDependencyManifest.expectedFrameworkNames.filter { frameworkName in
            let frameworkURL = frameworksDirectory
                .appendingPathComponent(frameworkName)
                .appendingPathExtension("xcframework")
            return RimeNativeDependencyManifest.supportsIOSSimulator(frameworkURL: frameworkURL)
        }

        XCTAssertEqual(Set(simulatorReady), Set(RimeNativeDependencyManifest.expectedFrameworkNames))
    }

    func testNativeChineseRimeBridgeProducesT9Candidates() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bridge = NativeChineseRimeBridge(
            mode: .chineseNineGrid,
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundle: try schemaResourceBundle()
        )

        try await bridge.start(hasFullAccess: false)
        let composition = try await bridge.input("6464")

        XCTAssertTrue(
            composition.candidates.map(\.text).contains("明")
                || composition.candidates.map(\.text).contains("宁"),
            "6464 candidates: \(composition.candidates.map(\.text))"
        )
    }

    func testNativeChineseRimeBridgeSwitchesFromPinyinToT9Schema() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bridge = NativeChineseRimeBridge(
            mode: .chineseQwerty,
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundle: try schemaResourceBundle()
        )
        let session = ChineseInputSession(mode: .chineseQwerty, bridge: bridge)

        try await session.start(hasFullAccess: false)
        _ = try await session.switchMode(.chineseNineGrid)
        let action = try await session.input("6464")

        guard case let .updateComposition(composition) = action else {
            XCTFail("Expected composition after T9 input, got \(action)")
            return
        }
        XCTAssertTrue(
            composition.candidates.map(\.text).contains("明")
                || composition.candidates.map(\.text).contains("宁"),
            "6464 candidates after schema switch: \(composition.candidates.map(\.text))"
        )
    }

    func testNativeChineseRimeBridgeExposesAndSelectsT9PinyinCandidates() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bridge = NativeChineseRimeBridge(
            mode: .chineseNineGrid,
            directories: .init(
                appGroupRoot: root.appendingPathComponent("AppGroup", isDirectory: true),
                sandboxRoot: root.appendingPathComponent("Sandbox", isDirectory: true)
            ),
            bundle: try schemaResourceBundle()
        )
        let session = ChineseInputSession(mode: .chineseNineGrid, bridge: bridge)

        try await session.start(hasFullAccess: false)
        let initialAction = try await session.input("94664")
        guard case let .updateComposition(initial) = initialAction else {
            XCTFail("Expected T9 composition")
            return
        }
        XCTAssertTrue(
            initial.pinyinCandidates.contains("xiong"),
            "preedit=\(initial.preedit) pinyinCandidates=\(initial.pinyinCandidates)"
        )
        XCTAssertTrue(
            initial.pinyinCandidates.contains("zhong"),
            "preedit=\(initial.preedit) pinyinCandidates=\(initial.pinyinCandidates)"
        )

        let selectedAction = try await session.selectPinyinCandidate("zhong")
        guard case let .updateComposition(selected) = selectedAction else {
            XCTFail("Expected composition after selecting pinyin")
            return
        }
        XCTAssertEqual(selected.selectedPinyin, "zhong")
        XCTAssertTrue(
            selected.candidates.map(\.text).contains("中"),
            "zhong candidates: \(selected.candidates.map(\.text))"
        )
    }

    private func schemaResourceBundle() throws -> Bundle {
        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            let allResourcesExist = RimeSchemaDeploymentPlan.requiredSchemaResourceNames.allSatisfy { name in
                let resource = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                return bundle.url(forResource: resource, withExtension: ext, subdirectory: "Schemas") != nil
                    || bundle.url(forResource: resource, withExtension: ext) != nil
            }
            if allResourcesExist {
                return bundle
            }
        }
        throw XCTSkip("ChineseInput schema resource bundle not found")
    }

    private func rimeFrameworksDirectory() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("ChineseInput", isDirectory: true)
                .appendingPathComponent("Frameworks", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
            current.deleteLastPathComponent()
        }
        throw XCTSkip("ChineseInput/Frameworks directory not found")
    }
}

private final class FakeChineseRimeBridge: ChineseRimeBridge {
    private(set) var state: ChineseCompositionState
    var states: [ChineseCompositionState]
    var selected: [ChineseCompositionState]
    var deleted: [ChineseCompositionState]
    var selectedIndexes: [Int] = []
    var resetCallCount = 0
    var status: ChineseInputStatus = .idle
    var additionalCandidatePages: [[CandidateSuggestion]]
    var requestedCandidateLimits: [Int] = []
    var selectedPinyinStates: [ChineseCompositionState]
    var selectedPinyinCandidates: [String] = []

    init(
        initial: ChineseCompositionState = .init(),
        states: [ChineseCompositionState] = [],
        selected: [ChineseCompositionState] = [],
        deleted: [ChineseCompositionState] = [],
        additionalCandidatePages: [[CandidateSuggestion]] = [],
        selectedPinyinStates: [ChineseCompositionState] = []
    ) {
        self.state = initial
        self.states = states
        self.selected = selected
        self.deleted = deleted
        self.additionalCandidatePages = additionalCandidatePages
        self.selectedPinyinStates = selectedPinyinStates
    }

    func start(hasFullAccess: Bool) async throws {}

    func switchMode(_ mode: ChineseInputMode) async throws -> ChineseCompositionState {
        state = .init()
        return state
    }

    func input(_ text: String) async throws -> ChineseCompositionState {
        if states.isEmpty {
            return state
        }
        state = states.removeFirst()
        return state
    }

    func selectCandidate(at index: Int) async throws -> ChineseCompositionState {
        selectedIndexes.append(index)
        if selected.isEmpty {
            return state
        }
        state = selected.removeFirst()
        return state
    }

    func deleteBackward() async throws -> ChineseCompositionState {
        if deleted.isEmpty {
            state = .init()
            return state
        }
        state = deleted.removeFirst()
        return state
    }

    func pageCandidates(from offset: Int, count: Int) async throws -> [CandidateSuggestion] { [] }
    func replacePreeditInput(_ replacement: String) async throws -> ChineseCompositionState { state }
    func loadMoreCandidates(limit: Int) async throws -> ChineseCompositionState {
        requestedCandidateLimits.append(limit)
        guard !additionalCandidatePages.isEmpty else {
            state.hasMoreCandidates = false
            return state
        }
        state.candidates.append(contentsOf: additionalCandidatePages.removeFirst().prefix(limit))
        state.hasMoreCandidates = !additionalCandidatePages.isEmpty || state.candidates.count < 100
        return state
    }

    func selectPinyinCandidate(_ candidate: String) async throws -> ChineseCompositionState {
        selectedPinyinCandidates.append(candidate)
        guard !selectedPinyinStates.isEmpty else { return state }
        state = selectedPinyinStates.removeFirst()
        return state
    }
    func reset() async {
        resetCallCount += 1
        state = .init()
    }
}
