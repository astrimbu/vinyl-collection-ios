import Foundation
import OSLog

enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        // Debug: Print all environment variables
        print("All environment variables:")
        ProcessInfo.processInfo.environment.forEach { key, value in
            print("\(key): \(value)")
        }
        
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else {
            print("❌ Missing key in Info.plist: \(key)")
            throw Error.missingKey
        }

        switch object {
        case let value as T:
            print("✅ Found value in Info.plist: \(value)")
            return value
        case let string as String:
            guard let value = T(string) else { fallthrough }
            print("✅ Found string in Info.plist and converted: \(value)")
            return value
        default:
            print("❌ Invalid value type in Info.plist for key: \(key)")
            throw Error.invalidValue
        }
    }
}

enum API {
    static var discogsToken: String {
        #if DEBUG
        // In debug, first try to get from environment
        if let token = ProcessInfo.processInfo.environment["DISCOGS_API_TOKEN"] {
            print("✅ Found Discogs token in environment variables")
            return token
        }
        print("❌ No Discogs token found in environment variables")
        #endif
        
        // For release builds, this should be set in Info.plist
        do {
            let token = try Configuration.value(for: "DISCOGS_API_TOKEN")
            print("✅ Found Discogs token in Info.plist")
            return token
        } catch {
            print("❌ Failed to get Discogs token: \(error)")
            fatalError("Discogs API token not found. Make sure it's set in environment or Info.plist")
        }
    }
} 