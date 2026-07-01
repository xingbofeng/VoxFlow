import Foundation

enum PagesReleaseMetadataClientError: Error, Equatable {
    case invalidResponse
    case missingVersion
    case missingTag
    case missingAssetName
    case invalidReleasePageURL(String)
    case invalidDownloadURL(String)
}

struct PagesReleaseMetadataClient: ReleaseMetadataClient {
    private let endpointURL: URL
    private let fallbackScriptURL: URL
    private let session: URLSession

    init(
        endpointURL: URL = URL(string: "https://mashangxie.app/release.json")!,
        fallbackScriptURL: URL = URL(string: "https://mashangxie.app/script.js")!,
        session: URLSession = .shared
    ) {
        self.endpointURL = endpointURL
        self.fallbackScriptURL = fallbackScriptURL
        self.session = session
    }

    func fetchLatestRelease() async throws -> RemoteRelease {
        do {
            let (data, response) = try await session.data(from: endpointURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw PagesReleaseMetadataClientError.invalidResponse
            }
            return try Self.decodeRelease(data: data)
        } catch {
            let (data, response) = try await session.data(from: fallbackScriptURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw PagesReleaseMetadataClientError.invalidResponse
            }
            return try Self.decodeReleaseScript(data: data)
        }
    }

    static func decodeReleaseScript(data: Data) throws -> RemoteRelease {
        let script = String(decoding: data, as: UTF8.self)
        let version = try quotedValue(named: "version", in: script)
        let tag = try quotedValue(named: "tag", in: script)
        let assetName = try quotedValue(named: "assetName", in: script)
        guard !version.isEmpty else {
            throw PagesReleaseMetadataClientError.missingVersion
        }
        guard !tag.isEmpty else {
            throw PagesReleaseMetadataClientError.missingTag
        }
        guard !assetName.isEmpty else {
            throw PagesReleaseMetadataClientError.missingAssetName
        }
        let releasePageURLString = "https://github.com/xingbofeng/VoxFlow/releases/tag/\(tag)"
        let downloadURLString = "https://github.com/xingbofeng/VoxFlow/releases/download/\(tag)/\(assetName)"
        guard let releasePageURL = URL(string: releasePageURLString) else {
            throw PagesReleaseMetadataClientError.invalidReleasePageURL(releasePageURLString)
        }
        guard let downloadURL = URL(string: downloadURLString) else {
            throw PagesReleaseMetadataClientError.invalidDownloadURL(downloadURLString)
        }
        return RemoteRelease(
            version: version,
            tagName: tag,
            releasePageURL: releasePageURL,
            downloadURL: downloadURL,
            releaseNotes: "",
            isDraft: false,
            isPrerelease: false
        )
    }

    private static func quotedValue(named name: String, in script: String) throws -> String {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*:\s*"([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(script.startIndex..<script.endIndex, in: script)
        guard let match = regex.firstMatch(in: script, range: range),
              let valueRange = Range(match.range(at: 1), in: script) else {
            switch name {
            case "version":
                throw PagesReleaseMetadataClientError.missingVersion
            case "tag":
                throw PagesReleaseMetadataClientError.missingTag
            default:
                throw PagesReleaseMetadataClientError.missingAssetName
            }
        }
        return String(script[valueRange])
    }

    static func decodeRelease(data: Data) throws -> RemoteRelease {
        let payload = try JSONDecoder().decode(PagesReleasePayload.self, from: data)
        guard !payload.version.isEmpty else {
            throw PagesReleaseMetadataClientError.missingVersion
        }
        guard !payload.tag.isEmpty else {
            throw PagesReleaseMetadataClientError.missingTag
        }
        guard let releasePageURL = URL(string: payload.releasePageURL) else {
            throw PagesReleaseMetadataClientError.invalidReleasePageURL(payload.releasePageURL)
        }
        guard let downloadURL = URL(string: payload.downloadURL) else {
            throw PagesReleaseMetadataClientError.invalidDownloadURL(payload.downloadURL)
        }

        return RemoteRelease(
            version: payload.version,
            tagName: payload.tag,
            releasePageURL: releasePageURL,
            downloadURL: downloadURL,
            releaseNotes: payload.releaseNotes,
            isDraft: payload.draft,
            isPrerelease: payload.prerelease
        )
    }
}

private struct PagesReleasePayload: Decodable {
    let version: String
    let tag: String
    let assetName: String
    let releasePageURL: String
    let downloadURL: String
    let releaseNotes: String
    let draft: Bool
    let prerelease: Bool
}
