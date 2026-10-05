import SwiftUI
import AuthenticationServices
import CryptoKit

// iOS OAuth client (public, no secret — PKCE only). Same jaybulb-signin GCP project as the web client.
let iosClientID = "337798947774-m4fkg9dprksbbu8rbhei08cm1riuajti.apps.googleusercontent.com"
let iosRedirectScheme = "com.googleusercontent.apps.337798947774-m4fkg9dprksbbu8rbhei08cm1riuajti"
let iosRedirectURI = iosRedirectScheme + ":/oauth2redirect"

// Sign in with Google through the system browser (ASWebAuthenticationSession), which Google allows.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuth()
    var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first ?? ASPresentationAnchor()
        #endif
    }

    /// `loginHint` preselects an address in Google's account chooser.
    func connect(loginHint: String? = nil, completion: @escaping (String?) -> Void) {
        var verifierBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, verifierBytes.count, &verifierBytes)
        let verifier = Data(verifierBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: iosClientID),
            .init(name: "redirect_uri", value: iosRedirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/gmail.modify"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        if let loginHint, !loginHint.isEmpty { comps.queryItems?.append(.init(name: "login_hint", value: loginHint)) }

        let s = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: iosRedirectScheme) { callbackURL, _ in
            guard let callbackURL, let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else { completion(nil); return }
            Task { completion(await GoogleAuth.shared.finish(code: code, verifier: verifier)) }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    // Exchanges the code directly with Google (public client, PKCE, no secret needed), then hands
    // the resulting tokens to sieve's own /auth/native to mint a session it can hand back as a bearer token.
    private func finish(code: String, verifier: String) async -> String? {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params = ["code": code, "client_id": iosClientID, "redirect_uri": iosRedirectURI, "grant_type": "authorization_code", "code_verifier": verifier]
        req.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let tok = try? JSONDecoder().decode(GoogleToken.self, from: data) else { return nil }

        var native = URLRequest(url: apiBase.appendingPathComponent("auth/native"))
        native.httpMethod = "POST"
        native.setValue("application/json", forHTTPHeaderField: "Content-Type")
        native.httpBody = try? JSONEncoder().encode(NativeAuth(access_token: tok.access_token, refresh_token: tok.refresh_token, expires_in: tok.expires_in, client_id: iosClientID))
        guard let (ndata, _) = try? await URLSession.shared.data(for: native),
              let sess = try? JSONDecoder().decode(NativeSession.self, from: ndata) else { return nil }
        return sess.token
    }
}

struct GoogleToken: Decodable { let access_token: String; let refresh_token: String; let expires_in: Int }
struct NativeAuth: Encodable { let access_token: String; let refresh_token: String; let expires_in: Int; let client_id: String }
struct NativeSession: Decodable { let token: String }
