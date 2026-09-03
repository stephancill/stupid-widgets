import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
import UIKit

struct AIChatMessage: Codable, Identifiable, Equatable {
  var id = UUID()
  var role: String
  var content: String
}

struct OpenAICredential: Codable {
  var accessToken: String
  var refreshToken: String
  var expiresAt: Date
  var accountID: String?
  var email: String?
}

enum AIClientError: LocalizedError {
  case invalidResponse
  case keychain(OSStatus)
  case server(String)
  case signedOut

  var errorDescription: String? {
    switch self {
    case .invalidResponse: "ChatGPT returned an invalid response."
    case .keychain(let status):
      "Keychain could not save ChatGPT credentials (status \(status))."
    case .server(let message): message
    case .signedOut: "Sign in with ChatGPT to use the AI assistant."
    }
  }
}

@MainActor
final class OpenAIAuth: ObservableObject {
  static let shared = OpenAIAuth()

  private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
  private let redirectURI = "http://localhost:1455/auth/callback"
  private let service = "net.stupidtech.stupidwidgets.openai"
  private let account = "chatgpt-oauth"
  private let presentationContext = AuthenticationPresentationContext()
  private var signInTask: Task<Void, Never>?
  private var authenticationSession: ASWebAuthenticationSession?
  private var authenticationContinuation: CheckedContinuation<URL, any Error>?
  private var callbackListener: NWListener?

  @Published private(set) var credential: OpenAICredential?
  @Published private(set) var isSigningIn = false
  @Published var errorMessage: String?

  var isSignedIn: Bool { credential != nil }

  private init() {
    credential = try? loadCredential()
  }

  func signIn() {
    guard !isSigningIn else { return }
    isSigningIn = true
    errorMessage = nil
    signInTask = Task {
      do {
        let pkce = try generatePKCE()
        let state = try randomBase64URL(byteCount: 32)
        let authorizationURL = try authorizeURL(pkce: pkce, state: state)
        let callbackURL = try await authenticate(at: authorizationURL)
        let code = try authorizationCode(from: callbackURL, expectedState: state)
        let tokens = try await exchange(code: code, verifier: pkce.verifier)
        try save(tokens)
      } catch is CancellationError {
      } catch {
        errorMessage = error.localizedDescription
      }
      isSigningIn = false
      authenticationSession = nil
    }
  }

  func cancelSignIn() {
    signInTask?.cancel()
    signInTask = nil
    finishAuthentication(with: .failure(CancellationError()))
    isSigningIn = false
  }

  func signOut() {
    cancelSignIn()
    #if targetEnvironment(simulator)
      UserDefaults.standard.removeObject(forKey: service)
    #else
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      SecItemDelete(query as CFDictionary)
    #endif
    credential = nil
  }

  func validCredential() async throws -> OpenAICredential {
    guard var current = credential else { throw AIClientError.signedOut }
    if current.expiresAt > Date().addingTimeInterval(300) { return current }

    var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = formBody([
      "grant_type": "refresh_token",
      "refresh_token": current.refreshToken,
      "client_id": clientID,
    ])
    let response: TokenResponse = try await decode(request)
    current = credential(from: response, fallbackRefreshToken: current.refreshToken)
    try save(current)
    return current
  }

  private struct PKCE {
    let verifier: String
    let challenge: String
  }

  private struct TokenResponse: Decodable {
    let idToken: String?
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?

    enum CodingKeys: String, CodingKey {
      case idToken = "id_token"
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case expiresIn = "expires_in"
    }
  }

  private func generatePKCE() throws -> PKCE {
    let verifier = try randomBase64URL(byteCount: 32)
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    return PKCE(verifier: verifier, challenge: challenge)
  }

  private func randomBase64URL(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw AIClientError.invalidResponse
    }
    return Data(bytes).base64URLEncodedString()
  }

  private func authorizeURL(pkce: PKCE, state: String) throws -> URL {
    var components = URLComponents(string: "https://auth.openai.com/oauth/authorize")
    components?.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "scope", value: "openid profile email offline_access"),
      URLQueryItem(name: "code_challenge", value: pkce.challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "id_token_add_organizations", value: "true"),
      URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "originator", value: "opencode"),
    ]
    guard let url = components?.url else { throw AIClientError.invalidResponse }
    return url
  }

  private func authenticate(at url: URL) async throws -> URL {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        authenticationContinuation = continuation
        do {
          try startCallbackListener(authorizationURL: url)
        } catch {
          finishAuthentication(with: .failure(error))
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.finishAuthentication(with: .failure(CancellationError()))
      }
    }
  }

  private func startCallbackListener(authorizationURL: URL) throws {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    guard let port = NWEndpoint.Port(rawValue: 1455) else { throw AIClientError.invalidResponse }
    let listener = try NWListener(using: parameters, on: port)
    listener.stateUpdateHandler = { [weak self] state in
      Task { @MainActor in
        guard let self else { return }
        switch state {
        case .ready:
          self.startAuthenticationSession(at: authorizationURL)
        case .failed(let error):
          self.finishAuthentication(with: .failure(error))
        default:
          break
        }
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      connection.start(queue: .global(qos: .userInitiated))
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
        data, _, _, error in
        Task { @MainActor in
          self?.handleCallbackConnection(connection, data: data, error: error)
        }
      }
    }
    callbackListener = listener
    listener.start(queue: .global(qos: .userInitiated))
  }

  private func startAuthenticationSession(at url: URL) {
    guard authenticationContinuation != nil, authenticationSession == nil else { return }
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) {
      [weak self] _, error in
      Task { @MainActor in
        guard let self else { return }
        if let error,
          (error as NSError).domain == ASWebAuthenticationSessionErrorDomain,
          (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
        {
          self.finishAuthentication(with: .failure(CancellationError()))
        } else {
          self.finishAuthentication(with: .failure(error ?? AIClientError.invalidResponse))
        }
      }
    }
    session.presentationContextProvider = presentationContext
    authenticationSession = session
    if !session.start() {
      finishAuthentication(with: .failure(AIClientError.invalidResponse))
    }
  }

  private func handleCallbackConnection(_ connection: NWConnection, data: Data?, error: Error?) {
    guard error == nil, let data, let request = String(data: data, encoding: .utf8),
      let requestLine = request.components(separatedBy: "\r\n").first
    else {
      connection.cancel()
      return
    }
    let parts = requestLine.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2,
      let baseURL = URL(string: redirectURI),
      let callbackURL = URL(string: String(parts[1]), relativeTo: baseURL)?.absoluteURL,
      callbackURL.path == "/auth/callback"
    else {
      sendCallbackResponse(
        status: "404 Not Found", body: "Not found", connection: connection, result: nil)
      return
    }
    sendCallbackResponse(
      status: "200 OK",
      body: "Authorization complete. You can return to stupid widgets.",
      connection: connection,
      result: .success(callbackURL)
    )
  }

  private func sendCallbackResponse(
    status: String, body: String, connection: NWConnection, result: Result<URL, any Error>?
  ) {
    let bodyData = Data(body.utf8)
    let headers = Data(
      "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        .utf8)
    connection.send(
      content: headers + bodyData,
      completion: .contentProcessed { [weak self] _ in
        connection.cancel()
        guard let result else { return }
        Task { @MainActor in self?.finishAuthentication(with: result) }
      })
  }

  private func finishAuthentication(with result: Result<URL, any Error>) {
    guard let continuation = authenticationContinuation else { return }
    authenticationContinuation = nil
    callbackListener?.cancel()
    callbackListener = nil
    authenticationSession?.cancel()
    authenticationSession = nil
    continuation.resume(with: result)
  }

  private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
    guard callbackURL.scheme == "http", callbackURL.host == "localhost", callbackURL.port == 1455,
      callbackURL.path == "/auth/callback",
      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
    else { throw AIClientError.invalidResponse }
    let queryItems = components.queryItems ?? []
    if let message = queryItems.first(where: { $0.name == "error_description" })?.value
      ?? queryItems.first(where: { $0.name == "error" })?.value
    {
      throw AIClientError.server(message)
    }
    let state = queryItems.first(where: { $0.name == "state" })?.value
    let code = queryItems.first(where: { $0.name == "code" })?.value
    guard state == expectedState, let code, !code.isEmpty else {
      throw AIClientError.invalidResponse
    }
    return code
  }

  private func exchange(code: String, verifier: String) async throws -> OpenAICredential {
    var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = formBody([
      "grant_type": "authorization_code",
      "code": code,
      "redirect_uri": redirectURI,
      "client_id": clientID,
      "code_verifier": verifier,
    ])
    let response: TokenResponse = try await decode(request)
    return credential(from: response, fallbackRefreshToken: "")
  }

  private func credential(from response: TokenResponse, fallbackRefreshToken: String)
    -> OpenAICredential
  {
    OpenAICredential(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken ?? fallbackRefreshToken,
      expiresAt: Date().addingTimeInterval(response.expiresIn ?? 3600),
      accountID: accountID(from: response.idToken) ?? accountID(from: response.accessToken),
      email: email(from: response.idToken) ?? email(from: response.accessToken)
    )
  }

  private func jwtClaims(from token: String?) -> [String: Any]? {
    guard let token, let payload = token.split(separator: ".").dropFirst().first else {
      return nil
    }
    var decoded = String(payload).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    decoded += String(repeating: "=", count: (4 - decoded.count % 4) % 4)
    guard let data = Data(base64Encoded: decoded),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return claims
  }

  private func accountID(from token: String?) -> String? {
    guard let claims = jwtClaims(from: token) else { return nil }
    return claims["chatgpt_account_id"] as? String
      ?? claims["https://api.openai.com/auth.chatgpt_account_id"] as? String
      ?? (claims["organizations"] as? [[String: Any]])?.first?["id"] as? String
  }

  private func email(from token: String?) -> String? {
    guard let claims = jwtClaims(from: token) else { return nil }
    if let email = claims["email"] as? String, !email.isEmpty { return email }
    return (claims["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String
  }

  private func save(_ value: OpenAICredential) throws {
    let data = try JSONEncoder().encode(value)
    #if targetEnvironment(simulator)
      UserDefaults.standard.set(data, forKey: service)
    #else
      let common: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      ]
      let query: [String: Any] = common
      let status = SecItemUpdate(
        query as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )
      if status == errSecItemNotFound {
        var item = common
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AIClientError.keychain(addStatus) }
      } else if status != errSecSuccess {
        throw AIClientError.keychain(status)
      }
    #endif
    credential = value
  }

  private func loadCredential() throws -> OpenAICredential? {
    #if targetEnvironment(simulator)
      guard let data = UserDefaults.standard.data(forKey: service) else { return nil }
    #else
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess, let data = result as? Data else {
        throw AIClientError.keychain(status)
      }
    #endif
    var value = try JSONDecoder().decode(OpenAICredential.self, from: data)
    if value.email == nil, let derived = email(from: value.accessToken) {
      value.email = derived
    }
    return value
  }

  private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw serverError(data: data, status: http.statusCode)
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func serverError(data: Data, status: Int) -> Error {
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    let message =
      object?["error_description"] as? String
      ?? (object?["error"] as? [String: Any])?["message"] as? String
      ?? "ChatGPT request failed (HTTP \(status))."
    return AIClientError.server(message)
  }

  private func formBody(_ values: [String: String]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let string = values.map { key, value in
      "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }.joined(separator: "&")
    return Data(string.utf8)
  }
}

@MainActor
private final class AuthenticationPresentationContext: NSObject,
  ASWebAuthenticationPresentationContextProviding
{
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      if let window = scene.windows.first(where: \.isKeyWindow) { return window }
    }
    return ASPresentationAnchor()
  }
}

extension Data {
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
