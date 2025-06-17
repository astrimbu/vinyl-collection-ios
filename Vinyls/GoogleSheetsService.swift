import Foundation
import AuthenticationServices

class GoogleSheetsService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    private let clientId = API.googleClientId
    private let clientSecret = API.googleClientSecret
    private let redirectUri = API.googleRedirectUri
    
    private var webAuthSession: ASWebAuthenticationSession?
    
    func authorize() {
        let scope = "https://www.googleapis.com/auth/drive.file"
        let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
        
        var urlComponents = URLComponents(string: authURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        webAuthSession = ASWebAuthenticationSession(
            url: urlComponents.url!,
            callbackURLScheme: "aeiou.Vinyls") { [weak self] callbackURL, error in
                guard error == nil, let callbackURL = callbackURL else {
                    print("Auth error:", error?.localizedDescription ?? "")
                    return
                }
                
                guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "code" })?
                    .value
                else {
                    print("No code in callback URL")
                    return
                }
                
                self?.exchangeCodeForToken(code)
            }
        
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = false 
        webAuthSession?.start()
    }
    
    private func exchangeCodeForToken(_ code: String) {
        let tokenURL = "https://oauth2.googleapis.com/token"
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var parameters: [String: String] = [
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        if !clientSecret.isEmpty {
            parameters["client_secret"] = clientSecret
        }
        
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data else {
                print("Token exchange error:", error?.localizedDescription ?? "")
                return
            }
            
            do {
                let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.isAuthenticated = true
                    // Store token response for later use
                    UserDefaults.standard.set(tokenResponse.accessToken, forKey: "googleAccessToken")
                    if let refresh = tokenResponse.refreshToken {
                        UserDefaults.standard.set(refresh, forKey: "googleRefreshToken")
                    }
                }
            } catch {
                if let raw = String(data: data, encoding: .utf8) {
                    print("Token decode error: \(error). Raw response: \(raw)")
                } else {
                    print("Token decode error: \(error). Could not decode raw response to string.")
                }
            }
        }.resume()
    }
    
    func exportToGoogleSheets(albums: [Album]) {
        // Always try to obtain a *fresh* access token first. If that fails, we fall back to the auth flow.
        obtainValidAccessToken { [weak self] token in
            guard let self = self, let accessToken = token else {
                self?.authorize()
                return
            }

            self.createSpreadsheet(accessToken: accessToken) { result in
                switch result {
                case .success(let spreadsheetId):
                    self.updateSpreadsheetData(spreadsheetId: spreadsheetId, albums: albums, accessToken: accessToken)
                case .failure(let error):
                    print("Error creating spreadsheet:", error)
                }
            }
        }
    }
    
    private func createSpreadsheet(accessToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let spreadsheet = [
            "properties": [
                "title": "My Vinyl Collection"
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: spreadsheet)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let spreadsheetId = json["spreadsheetId"] as? String else {
                completion(.failure(NSError(domain: "", code: -1)))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                print("❌ Sheets API error \(httpResponse.statusCode): \(body)")
                completion(.failure(NSError(domain: "", code: httpResponse.statusCode)))
                return
            }
            
            completion(.success(spreadsheetId))
        }.resume()
    }
    
    private func updateSpreadsheetData(spreadsheetId: String, albums: [Album], accessToken: String) {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/A1:E\(albums.count + 1)?valueInputOption=RAW")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert albums to 2D array for sheets
        var values: [[String]] = [["Title", "Artist", "Year", "Genre", "Notes"]]
        values.append(contentsOf: albums.map { album in
            [
                album.title ?? "",
                album.artist ?? "",
                String(album.year),
                album.genre ?? "",
                album.notes ?? ""
            ]
        })
        
        let body = ["values": values]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error updating spreadsheet:", error)
                return
            }
            
            print("Successfully exported to Google Sheets!")
        }.resume()
    }
    
    // MARK: - Token refresh helpers
    
    private func obtainValidAccessToken(completion: @escaping (String?) -> Void) {
        if let refreshToken = UserDefaults.standard.string(forKey: "googleRefreshToken") {
            refreshAccessToken(refreshToken: refreshToken) { token in
                completion(token)
            }
        } else if let accessToken = UserDefaults.standard.string(forKey: "googleAccessToken") {
            completion(accessToken)
        } else {
            completion(nil)
        }
    }
    
    private func refreshAccessToken(refreshToken: String, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var parameters = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        if !clientSecret.isEmpty {
            parameters["client_secret"] = clientSecret
        }
        
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                print("Refresh token error:", error?.localizedDescription ?? "Unknown")
                completion(nil)
                return
            }
            
            do {
                let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                UserDefaults.standard.set(tokenResponse.accessToken, forKey: "googleAccessToken")
                if let refresh = tokenResponse.refreshToken {
                    UserDefaults.standard.set(refresh, forKey: "googleRefreshToken")
                }
                completion(tokenResponse.accessToken)
            } catch {
                if let raw = String(data: data, encoding: .utf8) {
                    print("Refresh token decode error: \(error). Raw response: \(raw)")
                } else {
                    print("Refresh token decode error: \(error). Could not decode raw response to string.")
                }
                completion(nil)
            }
        }.resume()
    }
}

extension GoogleSheetsService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
} 