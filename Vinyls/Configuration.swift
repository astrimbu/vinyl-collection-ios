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