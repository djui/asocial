import XCTest
@testable import Asocial

final class RedirectTests: XCTestCase {
    private func target(_ platform: Platform, _ path: String) -> String? {
        let config = PageConfig(filters: platform.filters, itemSelector: platform.itemSelector)
        let url = URL(string: "https://\(platform.redirectHosts[0])\(path)")!
        guard let redirected = config.redirect(url) else { return nil }
        let components = URLComponents(url: redirected, resolvingAgainstBaseURL: false)!
        return components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    func testInstagram() {
        XCTAssertEqual(target(.instagram, "/reels/"), "/direct/inbox/")
        XCTAssertEqual(target(.instagram, "/reels/C9abc_1/"), "/reel/C9abc_1/")
        XCTAssertNil(target(.instagram, "/reel/C9abc_1/"))
        XCTAssertEqual(target(.instagram, "/explore/"), "/explore/search/")
        XCTAssertNil(target(.instagram, "/explore/search/"))
        XCTAssertNil(target(.instagram, "/explore/tags/cats/"))
        XCTAssertNil(target(.instagram, "/direct/inbox/"))
        XCTAssertNil(target(.instagram, "/djui/"))
    }

    func testYouTube() {
        XCTAssertEqual(target(.youtube, "/shorts/dQw4w9WgXcQ"), "/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(target(.youtube, "/shorts/dQw4w9WgXcQ?feature=share"), "/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(target(.youtube, "/shorts"), "/feed/subscriptions")
        XCTAssertEqual(target(.youtube, "/"), "/feed/subscriptions")
        XCTAssertNil(target(.youtube, "/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(target(.youtube, "/feed/subscriptions"))
        XCTAssertNil(target(.youtube, "/results?search_query=swift"))
    }

    func testFacebook() {
        XCTAssertEqual(target(.facebook, "/reels/"), "/")
        XCTAssertEqual(target(.facebook, "/watch/"), "/")
        XCTAssertEqual(target(.facebook, "/watch/?ref=tab"), "/")
        XCTAssertNil(target(.facebook, "/watch/?v=123"))
        XCTAssertNil(target(.facebook, "/reel/123"))
        XCTAssertEqual(target(.facebook, "/marketplace/"), "/")
        XCTAssertNil(target(.facebook, "/messages/"))
    }

    func testDisabledFilterLetsPathThrough() {
        let config = PageConfig(filters: Platform.youtube.filters.filter { $0.id != "youtube.shorts" }, itemSelector: "")
        XCTAssertNil(config.redirect(URL(string: "https://m.youtube.com/shorts/abc")!))
    }

    func testHosts() {
        XCTAssertTrue(Platform.youtube.keepsInside(URL(string: "https://accounts.google.com/signin")!))
        XCTAssertTrue(Platform.instagram.keepsInside(URL(string: "https://www.facebook.com/login")!))
        XCTAssertFalse(Platform.instagram.keepsInside(URL(string: "https://example.com/")!))
        XCTAssertFalse(Platform.facebook.keepsInside(URL(string: "https://notfacebook.com/")!))
    }

    func testConfigJSONHasEveryPart() throws {
        let json = PageConfig(filters: Platform.youtube.filters, itemSelector: "x").json
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual((object["redirects"] as? [Any])?.count, 3)
        XCTAssertEqual((object["scripts"] as? [Any])?.count, 1)
        XCTAssertEqual(object["itemSelector"] as? String, "x")
    }

    func testPageScriptIsBundled() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "asocial", withExtension: "js"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("__ASOCIAL_CONFIG__"))
    }
}
