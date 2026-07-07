import Foundation

/// Checks the GitHub Releases API for a newer tagged version than the one
/// installed (update-check R55, R57, R61). No Sparkle: this repo is SPM-only,
/// no Xcode project to embed a framework+XPC into, and swapping the running
/// bundle already broke TCC once before signing settled down (STATE.md) — a
/// passive "go download it yourself" check sidesteps that risk entirely.
public enum UpdateChecker {
    public struct ReleaseInfo: Equatable, Sendable {
        public let version: String
        public let url: URL
    }

    private static let repo = "patrickonofre/cross-desk"

    /// `nil` covers both "no newer release" and "check failed" (R61) — the
    /// caller never needs to tell them apart, it just retries next cycle.
    public static func checkLatestRelease(
        currentVersion: String,
        client: some HTTPClient = URLSession.shared
    ) async -> ReleaseInfo? {
        guard let endpoint = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: endpoint)
        // GitHub's API rejects requests with no User-Agent (403) — easy to
        // miss in testing since a browser/curl always sends one implicitly.
        request.setValue("CrossDesk-UpdateCheck", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await client.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard isNewer(release.tagName, than: currentVersion) else { return nil }
            guard let releaseURL = URL(string: release.htmlURL) else { return nil }
            return ReleaseInfo(version: displayVersion(release.tagName), url: releaseURL)
        } catch {
            Log.app.error("update check failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// `remote`/`local` as GitHub tags or bare versions ("v1.2.0", "1.2.0").
    /// Numeric, component-wise compare — a string compare would rank
    /// "1.10.0" below "1.9.0". Differing component counts pad the shorter
    /// side with 0 ("1.2" vs "1.2.0" reads as equal, not newer).
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = numericComponents(remote)
        let l = numericComponents(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    /// Strips the leading `v` and any `-prerelease`/`+build` metadata —
    /// what the UI shows ("Nova versão x.x.x disponível").
    static func displayVersion(_ raw: String) -> String {
        var s = raw
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[s.startIndex..<cut])
        }
        return s
    }

    /// Non-numeric components read as 0 — fails safe: an unparseable tag
    /// never outranks a well-formed installed version.
    private static func numericComponents(_ raw: String) -> [Int] {
        displayVersion(raw).split(separator: ".").map { Int($0) ?? 0 }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

/// Network seam for testing (same principle as `ConfigStore.fileURL` and
/// mac-metrics-view's injected `UserDefaults`) — `URLSession` already
/// satisfies this signature, no adapter needed.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}
