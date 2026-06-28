import Foundation

enum InterfaceLanguageRelauncher {
    static func launch(
        bundleURL: URL,
        currentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            shellCommand(
                bundlePath: bundleURL.path,
                currentProcessIdentifier: currentProcessIdentifier
            )
        ]
        try process.run()
    }

    static func shellCommand(bundlePath: String, currentProcessIdentifier: Int32) -> String {
        "while /bin/kill -0 \(currentProcessIdentifier) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open -n \(shellQuoted(bundlePath))"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
