import Foundation

enum API {
    static let discogsToken: String = {
        // First try to read from .env file
        if let envPath = Bundle.main.path(forResource: ".env", ofType: nil),
           let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
            let lines = contents.components(separatedBy: .newlines)
            for line in lines {
                if line.starts(with: "DISCOGS_API_TOKEN=") {
                    let token = String(line.dropFirst("DISCOGS_API_TOKEN=".count))
                    print("✅ Found Discogs token in .env file")
                    return token
                }
            }
        }
        
        // Fallback to environment variable
        if let token = ProcessInfo.processInfo.environment["DISCOGS_API_TOKEN"] {
            print("✅ Found Discogs token in environment")
            return token
        }
        
        fatalError("⚠️ DISCOGS_API_TOKEN not found in .env file or environment")
    }()
} 