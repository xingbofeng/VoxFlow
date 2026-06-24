@MainActor
protocol ReleaseMetadataClient {
    func fetchLatestRelease() async throws -> RemoteRelease
}
