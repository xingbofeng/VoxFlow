import Foundation

enum RuntimeEnvironment {
    static func isRunningUnderXCTest(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        bundlePaths: [String] = Bundle.allBundles.map(\.bundlePath) + Bundle.allFrameworks.map(\.bundlePath),
        classExists: (String) -> Bool = { NSClassFromString($0) != nil }
    ) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundlePath"] != nil {
            return true
        }

        if arguments.contains(where: isXCTestPathOrFlag) {
            return true
        }

        if bundlePaths.contains(where: isXCTestPathOrFlag) {
            return true
        }

        return classExists("XCTestCase") || classExists("XCTest.XCTestCase")
    }

    private static func isXCTestPathOrFlag(_ value: String) -> Bool {
        value == "-XCTest" || value.hasSuffix(".xctest") || value.contains(".xctest/")
    }
}
