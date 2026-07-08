import Foundation

/// Version comparison for the update-dismiss flow (sparkle-auto-update, R60):
/// deciding whether a version Sparkle just found is newer than whatever the
/// user last dismissed. Sparkle itself does the actual "is there an update"
/// fetch+compare against the appcast — this is only for our own
/// `dismissedUpdateVersion` gate on top of that.
public enum UpdateChecker {
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
