/// Credentials accepted by the Gemini Developer API adapter.
public enum GeminiAuthMode: Hashable, Sendable {
    /// Developer API key. Do not embed a production key in a shipped app.
    case apiKey(String)
    /// A developer proxy that supplies the Gemini credential server-side.
    case proxied(headers: [String: String])
}
