import SwiftUI
import WebKit

/// The page script's configuration for a set of filters, as the JSON `asocial.js` reads.
struct PageConfig {
    let filters: [Filter]
    let itemSelector: String

    var json: String {
        let object: [String: Any] = [
            "redirects": filters.flatMap(\.redirects).map { ["pattern": $0.pattern, "target": $0.target] },
            "selectors": filters.flatMap(\.selectors),
            "labels": filters.flatMap(\.labels),
            "scripts": filters.map(\.script).filter { !$0.isEmpty },
            "itemSelector": itemSelector,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Where a page load goes instead, or nil to let it through.
    func redirect(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let pathAndQuery = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        for redirect in filters.flatMap(\.redirects) {
            guard let regex = try? NSRegularExpression(pattern: redirect.pattern),
                  regex.firstMatch(in: pathAndQuery, range: NSRange(pathAndQuery.startIndex..., in: pathAndQuery)) != nil
            else { continue }
            guard let target = redirect.target(for: pathAndQuery) else { return nil }
            let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            components.percentEncodedPath = String(parts[0])
            components.percentEncodedQuery = parts.count > 1 ? String(parts[1]) : nil
            return components.url
        }
        return nil
    }
}

/// One tab's web view, kept alive across tab switches so each site stays where you left it.
@MainActor
final class Browser: NSObject, ObservableObject {
    let platform: Platform
    let webView: WKWebView

    @Published private(set) var progress: Double = 0
    @Published private(set) var isLoading = false
    @Published var external: ExternalLink?

    private var config: PageConfig
    private var observations: [NSKeyValueObservation] = []
    private static let pageScript: String = {
        let url = Bundle.main.url(forResource: "asocial", withExtension: "js")!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    init(platform: Platform) {
        self.platform = platform
        config = PageConfig(filters: FilterSettings.shared.enabled(for: platform), itemSelector: platform.itemSelector)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // Present as Safari, which the sites' sign-in pages accept.
        configuration.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        webView.scrollView.refreshControl = {
            let control = UIRefreshControl()
            control.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
            return control
        }()
        configuration.userContentController.add(WeakMessageHandler(self), name: "asocial")
        installScripts()

        observations = [
            webView.observe(\.estimatedProgress) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
        ]
        NotificationCenter.default.addObserver(self, selector: #selector(filtersChanged), name: .asocialFiltersChanged, object: nil)

        webView.load(URLRequest(url: platform.home))
    }

    func goHome() {
        webView.load(URLRequest(url: platform.home))
    }

    private func installScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let source = Self.pageScript.replacingOccurrences(of: "__ASOCIAL_CONFIG__", with: config.json)
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    @objc private func filtersChanged() {
        config = PageConfig(filters: FilterSettings.shared.enabled(for: platform), itemSelector: platform.itemSelector)
        installScripts()
        webView.reload()
    }

    @objc private func pullToRefresh(_ control: UIRefreshControl) {
        webView.reload()
        control.endRefreshing()
    }
}

extension Browser: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, action.targetFrame?.isMainFrame ?? true else { return .allow }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https"].contains(scheme) else {
            return ["about", "blob", "data"].contains(scheme) ? .allow : .cancel
        }
        if !platform.keepsInside(url) {
            external = ExternalLink(url: url)
            return .cancel
        }
        if platform.redirects(url), let target = config.redirect(url) {
            Stats.shared.record()
            webView.load(URLRequest(url: target))
            return .cancel
        }
        return .allow
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

extension Browser: WKUIDelegate {
    /// Links that ask for a new window open in this tab, or in Safari when they leave the site.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if platform.keepsInside(url) { webView.load(action.request) } else { external = ExternalLink(url: url) }
        }
        return nil
    }
}

extension Browser: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let count = (body["blocked"] as? Int ?? 0) + (body["hidden"] as? Int ?? 0)
        if count > 0 { Stats.shared.record(count) }
    }
}

/// Keeps the user content controller from retaining the browser.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

struct ExternalLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
