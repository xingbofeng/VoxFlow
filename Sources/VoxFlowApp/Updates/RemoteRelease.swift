import Foundation

struct RemoteRelease: Equatable {
    let version: String
    let tagName: String
    let releasePageURL: URL
    let downloadURL: URL
    let releaseNotes: String
    let isDraft: Bool
    let isPrerelease: Bool

    var isStableCandidate: Bool {
        !isDraft && !isPrerelease
    }
}
