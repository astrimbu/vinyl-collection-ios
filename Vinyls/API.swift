import Foundation

enum API {
    static let discogsToken: String = {
        guard let token = ProcessInfo.processInfo.environment["DISCOGS_API_TOKEN"] else {
            fatalError("⚠️ DISCOGS_API_TOKEN environment variable not set")
        }
        return token
    }()
} 