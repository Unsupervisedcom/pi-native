import SwiftUI
import WebKit

struct BrowserPaneView: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            addressBar
            Divider().overlay(.white.opacity(0.12))
            ZStack {
                WebViewRepresentable(model: model)
                    .opacity(model.hasLoadedOnce ? 1 : 0)

                if !model.hasLoadedOnce {
                    VStack(spacing: 18) {
                        Image(systemName: "globe")
                            .font(.system(size: 58, weight: .regular))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 8) {
                            Text("Start browsing")
                                .font(.title3.weight(.semibold))
                            Text("Enter a URL to open a page")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let error = model.loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Couldn\u{2019}t load page")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .medium))
                Text("New tab")
                    .font(.body.weight(.medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(true)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var addressBar: some View {
        HStack(spacing: 14) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .disabled(!model.canGoBack)
                .accessibilityLabel("Browser Back")

            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(!model.canGoForward)
                .accessibilityLabel("Browser Forward")

            Button { model.reload() } label: { Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise") }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isLoading ? "Stop Loading" : "Reload Page")

            TextField("Enter a URL ↗", text: $model.addressBarText)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .onSubmit { model.navigate(to: model.addressBarText) }

            Button {} label: { Image(systemName: "ellipsis") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var addressBarText = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var hasLoadedOnce = false
    @Published var loadError: String?

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func navigate(to input: String) {
        guard let url = Self.normalizeURL(input) else { return }
        loadError = nil
        hasLoadedOnce = true
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        if isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    /// Accepts either a URL (adds `https://` if no scheme) or a bare search
    /// query (falls back to a web search), matching the reference app's
    /// apparent address-bar behavior.
    static func normalizeURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // `URL(string:)` happily parses bare "host:port" input like
        // "localhost:3000" with scheme == "localhost" (anything before the
        // first colon is a valid URI scheme syntactically) — WKWebView can't
        // load that. Dev-server addresses are an extremely common thing to
        // type here for a coding-agent-adjacent browser, so special-case
        // them before the generic scheme check below. Found by adversarial
        // review.
        if let httpURL = Self.localDevServerURL(trimmed) {
            return httpURL
        }

        if let url = URL(string: trimmed), let scheme = url.scheme, Self.knownWebSchemes.contains(scheme.lowercased()) {
            return url
        }

        let looksLikeDomain = !trimmed.contains(" ") && trimmed.contains(".")
        if looksLikeDomain, let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    private static let knownWebSchemes: Set<String> = ["http", "https", "file", "about"]

    private static func localDevServerURL(_ trimmed: String) -> URL? {
        let localHosts = ["localhost", "127.0.0.1", "[::1]", "0.0.0.0"]
        for host in localHosts {
            if trimmed == host || trimmed.hasPrefix("\(host):") || trimmed.hasPrefix("\(host)/") {
                return URL(string: "http://\(trimmed)")
            }
        }
        return nil
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = true
            self.loadError = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = false
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            self.addressBarText = webView.url?.absoluteString ?? self.addressBarText
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            guard !Self.isBenignNavigationError(error) else { return }
            self.loadError = error.localizedDescription
        }
    }

    /// WKWebView reports normal, user-invisible events (a redirect, a
    /// reload/stop superseding an in-flight load) as navigation failures.
    /// Showing an error overlay for these looks broken even though nothing
    /// actually went wrong. Found by adversarial review.
    nonisolated static func isBenignNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            guard !Self.isBenignNavigationError(error) else { return }
            self.loadError = error.localizedDescription
        }
    }
}

private struct WebViewRepresentable: NSViewRepresentable {
    let model: BrowserModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
