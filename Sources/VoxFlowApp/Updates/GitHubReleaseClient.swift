import Foundation

enum GitHubReleaseClientError: Error, Equatable {
    case invalidResponse
    case missingTag
    case missingReleasePageURL
    case invalidReleasePageURL(String)
}

struct GitHubReleaseClient: ReleaseMetadataClient {
    private let endpointURL: URL
    private let session: URLSession

    init(
        endpointURL: URL = URL(string: "https://api.github.com/repos/xingbofeng/VoxFlow/releases/latest")!,
        session: URLSession = .shared
    ) {
        self.endpointURL = endpointURL
        self.session = session
    }

    func fetchLatestRelease() async throws -> RemoteRelease {
        let (data, response) = try await session.data(from: endpointURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubReleaseClientError.invalidResponse
        }
        return try Self.decodeRelease(data: data)
    }

    static func decodeRelease(data: Data) throws -> RemoteRelease {
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard !payload.tagName.isEmpty else {
            throw GitHubReleaseClientError.missingTag
        }
        guard !payload.htmlURL.isEmpty else {
            throw GitHubReleaseClientError.missingReleasePageURL
        }
        guard let releasePageURL = URL(string: payload.htmlURL) else {
            throw GitHubReleaseClientError.invalidReleasePageURL(payload.htmlURL)
        }

        let downloadURL = payload.assets
            .first(where: { asset in
                asset.name.hasPrefix("VoxFlow-") && asset.name.hasSuffix("-macOS.dmg")
            })
            .flatMap { URL(string: $0.browserDownloadURL) }
            ?? releasePageURL

        return RemoteRelease(
            version: normalizedVersion(from: payload.tagName),
            tagName: payload.tagName,
            releasePageURL: releasePageURL,
            downloadURL: downloadURL,
            releaseNotes: payload.body,
            isDraft: payload.draft,
            isPrerelease: payload.prerelease
        )
    }

    private static func normalizedVersion(from tagName: String) -> String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAssetPayload: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
