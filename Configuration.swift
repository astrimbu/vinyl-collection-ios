import Foundation
import OSLog

enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        print("🔍 Attempting to load value for key: \(key)")
        
        // Debug: Print all environment variables
        print("📝 Environment variables:")
        ProcessInfo.processInfo.environment.forEach { key, value in
            print("   \(key): \(value.prefix(5))...")
        }
        
        print("📦 Checking Info.plist for key: \(key)")
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else {
            print("❌ Missing key in Info.plist: \(key)")
            throw Error.missingKey
        }

        switch object {
        case let value as T:
            print("✅ Found value in Info.plist: \(String(describing: value).prefix(5))...")
            return value
        case let string as String:
            guard let value = T(string) else { fallthrough }
            print("✅ Found string in Info.plist and converted: \(String(describing: value).prefix(5))...")
            return value
        default:
            print("❌ Invalid value type in Info.plist for key: \(key)")
            throw Error.invalidValue
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
            let token = try Configuration.value(for: "DISCOGS_API_TOKEN")
            print("✅ Found Discogs token in Info.plist: \(String(describing: token).prefix(5))...")
            return token
        } catch {
            print("❌ Failed to get Discogs token: \(error). Continuing with empty token; Discogs calls will be disabled.")
            return ""
        }
    }
} 