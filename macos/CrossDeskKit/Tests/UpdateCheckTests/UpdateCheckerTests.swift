import XCTest
@testable import CrossDeskKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: - isNewer

    func testIsNewer_greaterPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.0.1", than: "1.0.0"))
    }

    func testIsNewer_equalIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
    }

    func testIsNewer_lesserIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.9.0", than: "1.0.0"))
    }

    func testIsNewer_vPrefixIgnored() {
        XCTAssertTrue(UpdateChecker.isNewer("v2.0.0", than: "1.9.9"))
    }

    func testIsNewer_prereleaseSuffixStripped() {
        // Tag has "-beta.3" but the numeric part ties the installed version —
        // must not read as newer just because the string differs.
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0-beta.3", than: "1.0.0"))
    }

    func testIsNewer_malformedTagIsNeverNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("not-a-version", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.0.0"))
    }

    func testIsNewer_differentComponentCountsPadWithZero() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
    }

    func testIsNewer_numericCompareNotLexicographic() {
        // A string compare would rank "1.10.0" below "1.9.0" — this is the
        // exact bug class Sparkle's own comparator avoids.
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
    }

    // MARK: - checkLatestRelease

    private func makeResponse(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/patrickonofre/cross-desk/releases/latest")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    func testCheckLatestRelease_returnsInfoWhenNewer() async {
        let json = """
        {"tag_name": "v9.9.9", "html_url": "https://github.com/patrickonofre/cross-desk/releases/tag/v9.9.9"}
        """
        let client = FakeHTTPClient(result: .success((Data(json.utf8), makeResponse())))

        let result = await UpdateChecker.checkLatestRelease(currentVersion: "1.0.0", client: client)

        XCTAssertEqual(result?.version, "9.9.9")
        XCTAssertEqual(result?.url.absoluteString, "https://github.com/patrickonofre/cross-desk/releases/tag/v9.9.9")
    }

    func testCheckLatestRelease_returnsNilWhenNotNewer() async {
        let json = """
        {"tag_name": "v1.0.0", "html_url": "https://github.com/patrickonofre/cross-desk/releases/tag/v1.0.0"}
        """
        let client = FakeHTTPClient(result: .success((Data(json.utf8), makeResponse())))

        let result = await UpdateChecker.checkLatestRelease(currentVersion: "1.0.0", client: client)

        XCTAssertNil(result)
    }

    func testCheckLatestRelease_returnsNilOnMalformedJSON() async {
        let client = FakeHTTPClient(result: .success((Data("not json".utf8), makeResponse())))

        let result = await UpdateChecker.checkLatestRelease(currentVersion: "1.0.0", client: client)

        XCTAssertNil(result)
    }

    func testCheckLatestRelease_returnsNilOnHTTPErrorStatus() async {
        let client = FakeHTTPClient(result: .success((Data(), makeResponse(statusCode: 404))))

        let result = await UpdateChecker.checkLatestRelease(currentVersion: "1.0.0", client: client)

        XCTAssertNil(result)
    }

    func testCheckLatestRelease_returnsNilOnNetworkError() async {
        struct DummyError: Error {}
        let client = FakeHTTPClient(result: .failure(DummyError()))

        let result = await UpdateChecker.checkLatestRelease(currentVersion: "1.0.0", client: client)

        XCTAssertNil(result)
    }
}

private struct FakeHTTPClient: HTTPClient {
    let result: Result<(Data, URLResponse), Error>

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try result.get()
    }
}
