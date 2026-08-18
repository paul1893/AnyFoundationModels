public enum AuthMode: Hashable, Sendable {
  /// Developer-supplied API key. Bundled keys are extractable from a shipping
  /// app; for production, use ``proxied(headers:)``.
  case apiKey(String)
  /// Route requests through a developer-run proxy that adds the real credential
  /// server-side. `baseURL` points at the proxy; `headers` are sent on every
  /// request so the proxy can authorize the caller (e.g. a per-app secret or
  /// tenant id). Pass `[:]` when the proxy needs no client-supplied headers.
  ///
  /// These headers are fixed at construction. Per-request values (a rotating
  /// user token) belong in a future provider-based mode, not here.
  case proxied(headers: [String: String])
}
