import Foundation

enum BuiltinAgentFileSearchSupport {
    private static let excludedDirectoryNames = Set([
        ".git",
        ".svn",
        ".hg",
        ".bzr",
        ".jj",
        ".sl"
    ])

    struct FileRecord {
        let url: URL
        let relativePath: String
        let modifiedAt: Date
    }

    static func regularFiles(under root: URL) throws -> [FileRecord] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [FileRecord] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if excludedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            files.append(
                FileRecord(
                    url: url,
                    relativePath: relativePath(from: root, to: url),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }
        return files.sorted {
            if $0.relativePath == $1.relativePath {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.relativePath < $1.relativePath
        }
    }

    static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    static func matchesGlob(_ path: String, pattern: String) -> Bool {
        let candidates = pattern.contains("/")
            ? [path]
            : [path, (path as NSString).lastPathComponent]
        return candidates.contains { candidate in
            candidate.range(
                of: regexSource(forGlob: pattern),
                options: [.regularExpression]
            ) != nil
        }
    }

    private static func regexSource(forGlob pattern: String) -> String {
        var result = "^"
        let characters = Array(pattern)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    if index + 2 < characters.count, characters[index + 2] == "/" {
                        result += "(?:.*/)?"
                        index += 3
                    } else {
                        result += ".*"
                        index += 2
                    }
                } else {
                    result += "[^/]*"
                    index += 1
                }
                continue
            }
            if character == "?" {
                result += "[^/]"
                index += 1
                continue
            }
            if character == "{" {
                var end = index + 1
                while end < characters.count, characters[end] != "}" {
                    end += 1
                }
                if end < characters.count {
                    let body = String(characters[(index + 1)..<end])
                    let alternatives = body
                        .split(separator: ",")
                        .map { NSRegularExpression.escapedPattern(for: String($0)) }
                        .joined(separator: "|")
                    result += "(?:\(alternatives))"
                    index = end + 1
                    continue
                }
            }
            result += NSRegularExpression.escapedPattern(for: String(character))
            index += 1
        }

        result += "$"
        return result
    }
}
