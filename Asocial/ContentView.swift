import SafariServices
import SwiftUI
import WebKit

struct ContentView: View {
    @AppStorage("tab") private var tab = Platform.instagram.rawValue
    @StateObject private var browsers = Browsers()

    var body: some View {
        TabView(selection: $tab) {
            ForEach(Platform.allCases) { platform in
                BrowserScreen(browser: browsers[platform])
                    .tabItem { Label(platform.name, systemImage: platform.symbol) }
                    .tag(platform.rawValue)
            }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag("settings")
        }
    }
}

/// The tabs' browsers, made on first visit so an unopened site never loads.
@MainActor
final class Browsers: ObservableObject {
    private var made: [Platform: Browser] = [:]

    subscript(platform: Platform) -> Browser {
        if let browser = made[platform] { return browser }
        let browser = Browser(platform: platform)
        made[platform] = browser
        return browser
    }
}

struct BrowserScreen: View {
    @ObservedObject var browser: Browser

    var body: some View {
        WebView(webView: browser.webView)
            .overlay(alignment: .top) {
                if browser.isLoading {
                    ProgressView(value: browser.progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(height: 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: browser.isLoading)
            .sheet(item: $browser.external) { link in
                SafariView(url: link.url).ignoresSafeArea()
            }
    }
}

struct WebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
