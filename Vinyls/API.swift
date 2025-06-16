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
            print("❌ Failed to get Discogs token: \(error)")
            fatalError("Discogs API token not found. Make sure it's set in environment or Info.plist")
        }
    }

    static var googleClientId: String {
        ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"] ?? ""
    }
    
    static var googleClientSecret: String {
        ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"] ?? ""
    }
    
    static var googleRedirectUri: String {
        ProcessInfo.processInfo.environment["GOOGLE_REDIRECT_URI"] ?? ""
    }
} 