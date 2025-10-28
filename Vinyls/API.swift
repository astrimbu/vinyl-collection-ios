import Foundation
import OSLog

enum API {
    static var discogsConsumerKey: String {
        do {
            let key: String = try Configuration.value(for: "DISCOGS_CONSUMER_KEY")
            return key
        } catch {
            return ""
        }
    }

    static var discogsConsumerSecret: String {
        do {
            let secret: String = try Configuration.value(for: "DISCOGS_CONSUMER_SECRET")
            return secret
        } catch {
            return ""
        }
    }
    static let discogsToken: String = {
        // Compute once to avoid repeated logs on frequent view updates
        #if DEBUG
        if let token = ProcessInfo.processInfo.environment["DISCOGS_API_TOKEN"] {
            print("🔑 Discogs token loaded from environment (\(token.prefix(5))…)")
            return token
        }
        #endif
        do {
            let token: String = try Configuration.value(for: "DISCOGS_API_TOKEN")
            print("🔑 Discogs token loaded from Info.plist (\(token.prefix(5))…)")
            return token
        } catch {
            print("❌ Failed to get Discogs token: \(error). Discogs calls will be disabled.")
            return ""
        }
    }()
    
    static var googleClientId: String {
        #if DEBUG
        if let id = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] {
            return id
        }
        #endif
        do {
            let id: String = try Configuration.value(for: "GOOGLE_CLIENT_ID")
            return id
        } catch {
            fatalError("GOOGLE_CLIENT_ID not found in environment or Info.plist")
        }
    }
    
    static var googleClientSecret: String {
        #if DEBUG
        if let secret = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"] {
            return secret
        }
        #endif
        do {
            let secret: String = try Configuration.value(for: "GOOGLE_CLIENT_SECRET")
            return secret
        } catch {
            fatalError("GOOGLE_CLIENT_SECRET not found in environment or Info.plist")
        }
    }
    
    static var googleRedirectUri: String {
        #if DEBUG
        if let uri = ProcessInfo.processInfo.environment["GOOGLE_REDIRECT_URI"] {
            return uri
        }
        #endif
        do {
            let uri: String = try Configuration.value(for: "GOOGLE_REDIRECT_URI")
            return uri
        } catch {
            fatalError("GOOGLE_REDIRECT_URI not found in environment or Info.plist")
        }
    }
} 