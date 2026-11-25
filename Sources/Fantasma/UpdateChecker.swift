import Foundation

struct FantasmaVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0,
              let patch = Int(parts[2]), patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

enum UpdateCheckResult {
    case current
    case available(FantasmaVersion, URL)
}

enum UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/andrew-bierman/fantasma/releases/latest")!

    enum CheckError: Error {
        case invalidResponse
        case invalidVersion
    }

    private struct Release: Decodable {
        let tag_name: String
    }

    static func result(currentVersion: String, latestTag: String) throws -> UpdateCheckResult {
        guard let current = FantasmaVersion(currentVersion),
              let latest = FantasmaVersion(latestTag) else { throw CheckError.invalidVersion }
        guard latest > current else { return .current }
        let url = URL(string: "https://github.com/andrew-bierman/fantasma/releases/tag/v\(latest)")!
        return .available(latest, url)
    }

    static func check(currentVersion: String) async throws -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Fantasma-update-check", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw CheckError.invalidResponse
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return try result(currentVersion: currentVersion, latestTag: release.tag_name)
    }
}
