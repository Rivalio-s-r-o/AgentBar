import Foundation

/// Sémantická verze major.minor.patch. Tolerantní parse, NUMERICKÉ porovnání (0.10 > 0.9).
public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int
    public init(major: Int, minor: Int, patch: Int) { self.major = major; self.minor = minor; self.patch = patch }

    public static func parse(_ s: String) -> SemanticVersion? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = t.first, f == "v" || f == "V" { t.removeFirst() }
        // odřízni prerelease/build metadata (1.2.3-beta / 1.2.3+build)
        t = t.components(separatedBy: CharacterSet(charactersIn: "-+")).first ?? t
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var nums = [0, 0, 0]
        for (i, p) in parts.enumerated() {
            guard let n = Int(p), n >= 0 else { return nil }
            nums[i] = n
        }
        return SemanticVersion(major: nums[0], minor: nums[1], patch: nums[2])
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if a.major != b.major { return a.major < b.major }
        if a.minor != b.minor { return a.minor < b.minor }
        return a.patch < b.patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public enum UpdateStatus: Sendable, Equatable {
    case upToDate(SemanticVersion)
    case updateAvailable(version: SemanticVersion, url: String)
    case unknown
}

/// Vyhodnocení aktualizace z (current, latestTag, latestURL). Čisté — síť je injektovaná zvenčí.
public enum UpdateChecker {
    public static func evaluate(current: SemanticVersion, latestTag: String?, latestURL: String?) -> UpdateStatus {
        guard let tag = latestTag, let latest = SemanticVersion.parse(tag) else { return .unknown }
        if latest > current {
            return .updateAvailable(version: latest, url: latestURL ?? "https://github.com/Rivalio-s-r-o/AgentBar/releases")
        }
        return .upToDate(current)
    }
}
