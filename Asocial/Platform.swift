import Foundation

/// A site Asocial wraps, with the filters that take its endless feeds out.
enum Platform: String, CaseIterable, Identifiable {
    case instagram, youtube, facebook

    var id: String { rawValue }

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .facebook: "Facebook"
        }
    }

    /// SF Symbol for the tab. Asocial doesn't ship the sites' logos.
    var symbol: String {
        switch self {
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .facebook: "person.2"
        }
    }

    var home: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/")!
        case .youtube: URL(string: "https://m.youtube.com/feed/subscriptions")!
        case .facebook: URL(string: "https://m.facebook.com/")!
        }
    }

    /// Hosts that open inside the tab, including the sign-in flows each site sends you through.
    /// Any other link opens in a Safari sheet.
    var hostSuffixes: [String] {
        switch self {
        case .instagram: ["instagram.com", "facebook.com", "fbcdn.net", "cdninstagram.com", "accountscenter.instagram.com"]
        case .youtube: ["youtube.com", "youtu.be", "google.com", "gstatic.com", "googleusercontent.com", "googlevideo.com", "ytimg.com"]
        case .facebook: ["facebook.com", "fb.com", "fbcdn.net", "messenger.com", "fb.me"]
        }
    }

    /// Hosts the filters' redirects apply to.
    var redirectHosts: [String] {
        switch self {
        case .instagram: ["instagram.com"]
        case .youtube: ["youtube.com"]
        case .facebook: ["facebook.com"]
        }
    }

    /// Feed items a hidden label takes with it. Empty means: the nearest ancestor that looks like a post.
    var itemSelector: String {
        switch self {
        case .instagram: "article"
        case .youtube: "ytm-rich-item-renderer, ytm-rich-section-renderer, ytm-item-section-renderer, ytm-video-with-context-renderer"
        case .facebook: ""
        }
    }

    func keepsInside(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return hostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func redirects(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return redirectHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    var filters: [Filter] {
        switch self {
        case .instagram: Filter.instagram
        case .youtube: Filter.youtube
        case .facebook: Filter.facebook
        }
    }
}

/// Sends a path somewhere calmer. `pattern` is a regular expression over path and query, written so
/// that JavaScript and NSRegularExpression read it the same; `target` may use `$1`…`$9`.
struct Redirect: Equatable {
    let pattern: String
    let target: String

    /// Where `pathAndQuery` goes instead, or nil when this redirect leaves it alone.
    func target(for pathAndQuery: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: pathAndQuery, range: NSRange(pathAndQuery.startIndex..., in: pathAndQuery))
        else { return nil }
        var result = target
        for group in stride(from: min(match.numberOfRanges - 1, 9), through: 1, by: -1) {
            let range = Range(match.range(at: group), in: pathAndQuery)
            result = result.replacingOccurrences(of: "$\(group)", with: range.map { String(pathAndQuery[$0]) } ?? "")
        }
        return result == pathAndQuery ? nil : result
    }
}

/// One thing Asocial takes out of a site, which you can switch back on in Settings.
struct Filter: Identifiable {
    let id: String
    let title: String
    let detail: String
    var redirects: [Redirect] = []
    /// CSS selectors hidden outright. `html[data-asocial-path^="/x"]` scopes one to a page.
    var selectors: [String] = []
    /// Exact texts (like "Sponsored") whose feed item is hidden.
    var labels: [String] = []
    /// Extra JavaScript, run once per page.
    var script: String = ""
}

extension Filter {
    static let instagram: [Filter] = [
        Filter(
            id: "instagram.reels", title: "Reels",
            detail: "The Reels tab and feed. A reel someone sends you still plays — just that one.",
            redirects: [
                Redirect(pattern: #"^/reels/?(\?.*)?$"#, target: "/direct/inbox/"),
                Redirect(pattern: #"^/reels/([^/?]+)"#, target: "/reel/$1/"),
            ],
            selectors: [
                #"a[href="/reels/"]"#,
                #"div:has(> a[href="/reels/"])"#,
                #"html[data-asocial-path^="/reel/"] main section ~ div:has(a[href^="/reel/"])"#,
            ]
        ),
        Filter(
            id: "instagram.explore", title: "Explore",
            detail: "The Explore grid. Search stays, without the grid of picks under it.",
            redirects: [Redirect(pattern: #"^/explore/?(\?.*)?$"#, target: "/explore/search/")],
            selectors: [
                #"html[data-asocial-path^="/explore/search"] main a[href^="/p/"]"#,
                #"html[data-asocial-path^="/explore/search"] main a[href^="/reel/"]"#,
            ]
        ),
        Filter(
            id: "instagram.suggested", title: "Suggested posts",
            detail: "Posts and accounts from people you don't follow.",
            labels: ["Suggested for you", "Suggested posts", "Suggested reels", "Suggested threads"]
        ),
        Filter(
            id: "instagram.ads", title: "Ads",
            detail: "Sponsored posts in your feed and stories.",
            labels: ["Sponsored"]
        ),
    ]

    static let youtube: [Filter] = [
        Filter(
            id: "youtube.shorts", title: "Shorts",
            detail: "The Shorts tab and shelves. A short someone sends you opens as a normal video, with no swipe to the next.",
            redirects: [
                Redirect(pattern: #"^/shorts/?(\?.*)?$"#, target: "/feed/subscriptions"),
                Redirect(pattern: #"^/shorts/([^/?]+)"#, target: "/watch?v=$1"),
            ],
            selectors: [
                "ytm-reel-shelf-renderer",
                "ytm-shorts-lockup-view-model",
                "ytm-shorts-lockup-view-model-v2",
                "ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model)",
                "grid-shelf-view-model:has(ytm-shorts-lockup-view-model)",
                "ytm-pivot-bar-item-renderer:has(.pivot-shorts)",
                #"ytm-video-with-context-renderer:has(a[href^="/shorts"])"#,
                #"a[href^="/shorts"]"#,
            ]
        ),
        Filter(
            id: "youtube.home", title: "Home feed",
            detail: "The recommended Home feed. Asocial opens Subscriptions instead.",
            redirects: [Redirect(pattern: #"^/(\?.*)?$"#, target: "/feed/subscriptions")],
            selectors: ["ytm-pivot-bar-item-renderer:has(.pivot-w2w)"]
        ),
        Filter(
            id: "youtube.upnext", title: "Up next",
            detail: "Recommendations under a video, autoplay, and the end-screen wall.",
            selectors: [
                #"ytm-item-section-renderer[section-identifier="related-items"]"#,
                "ytm-watch-next-secondary-results-renderer",
                "ytm-single-column-watch-next-results-renderer ytm-reel-shelf-renderer",
                ".ytm-autonav-toggle-button-container",
                ".ytp-autonav-toggle",
                ".ytp-endscreen-content",
                ".videowall-endscreen",
                ".ytp-ce-element",
            ]
        ),
        Filter(
            id: "youtube.ads", title: "Ads",
            detail: "Promoted videos and banners, and video ads skipped as soon as they start.",
            selectors: [
                "ytm-promoted-sparkles-web-renderer",
                "ytm-promoted-video-renderer",
                "ytm-companion-ad-renderer",
                "ytm-ad-slot-renderer",
                "ad-slot-renderer",
                "ytm-statement-banner-renderer",
                ".ytp-ad-overlay-container",
            ],
            script: """
            setInterval(() => {
              const video = document.querySelector('.ad-showing video');
              if (video && isFinite(video.duration)) { video.muted = true; video.currentTime = video.duration; }
              const skip = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
              if (skip) skip.click();
            }, 400);
            """
        ),
    ]

    static let facebook: [Filter] = [
        Filter(
            id: "facebook.reels", title: "Reels",
            detail: "The Reels feed and the reels shelves in your feed. A reel someone sends you still plays.",
            redirects: [Redirect(pattern: #"^/reels?/?(\?.*)?$"#, target: "/")],
            selectors: [#"a[href^="/reels"]"#, #"a[href*="facebook.com/reels"]"#],
            labels: ["Reels and short videos"]
        ),
        Filter(
            id: "facebook.video", title: "Video tab",
            detail: "The endless video feed. A video someone shares with you still plays.",
            redirects: [Redirect(pattern: #"^/(watch|video)/?(\?(?!v=).*)?$"#, target: "/")],
            selectors: [#"a[href="/watch/"]"#, #"a[href="/watch"]"#, #"a[href^="/video/"]"#]
        ),
        Filter(
            id: "facebook.suggested", title: "Suggested posts",
            detail: "Posts, groups, and people Facebook picked for you.",
            labels: ["Suggested for you", "Suggested groups", "People you may know", "Suggested for You"]
        ),
        Filter(
            id: "facebook.ads", title: "Ads",
            detail: "Sponsored posts in your feed.",
            labels: ["Sponsored"]
        ),
        Filter(
            id: "facebook.marketplace", title: "Marketplace",
            detail: "The Marketplace tab and shopping feed.",
            redirects: [Redirect(pattern: #"^/marketplace"#, target: "/")],
            selectors: [#"a[href^="/marketplace"]"#]
        ),
    ]
}
