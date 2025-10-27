import Foundation
import OSLog

enum API {
    static var discogsToken: String {
        print("🎯 Getting Discogs token...")
        
        #if DEBUG
        print("🐛 Debug mode: checking environment variables first")
        // In debug, first try to get from environment
        if let token = ProcessInfo.processInfo.environment["DISCOGS_API_TOKEN"] {
            print("✅ Found Discogs token in environment variables: \(token.prefix(5))...")
            return token
        }
        print("⚠️ No Discogs token found in environment variables")
        #endif
        
        // For release builds, this should be set in Info.plist
        do {
            print("📱 Attempting to load token from Info.plist")
            let token: String = try Configuration.value(for: "DISCOGS_API_TOKEN")
            print("✅ Found Discogs token in Info.plist: \(String(describing: token).prefix(5))...")
            return token
        } catch {
            print("❌ Failed to get Discogs token: \(error). Continuing with empty token; Discogs calls will be disabled.")
            return ""
        }
    }

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