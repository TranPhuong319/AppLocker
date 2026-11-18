//
//  UpdatePolicy.swift
//  AppLocker
//
//  Created by Doe Phương on 18/11/26.
//

import Foundation

enum Channel: Sendable {
    case stable
    case beta
}

enum UpdateDownloadState: Sendable {
    case notDownloaded
    case downloaded
}

struct BetaGitHubRelease: Decodable, Sendable {
    let prerelease: Bool
    let assets: [BetaGitHubAsset]
}

struct BetaGitHubAsset: Decodable, Sendable {
    let name: String
    let browserDownloadUrl: String
}

enum BetaFeedError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(
            localized: """
            Could not fetch the latest beta release from GitHub. \
            Please check your internet connection or try again later.
            """
        )
    }
}

enum UpdatePolicy {
    static let betaReleasesEndpoint = URL(string: "https://api.github.com/repos/TranPhuong319/AppLocker/releases")

    static func channel(from rawValue: String?) -> Channel {
        rawValue == "Beta" ? .beta : .stable
    }

    static func feedURLString(channel: Channel, betaFeedURL: String?) -> String? {
        channel == .beta ? betaFeedURL : nil
    }

    static func validateUpdateCheck(channel: Channel, betaFeedURL: String?) throws {
        if channel == .beta, betaFeedURL == nil {
            throw BetaFeedError.unavailable
        }
    }

    static func extractBetaAppcastURL(from data: Data) throws -> String? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let releases = try decoder.decode([BetaGitHubRelease].self, from: data)
        return releases
            .first(where: { $0.prerelease })?
            .assets
            .first(where: { $0.name == "appcast.xml" })?
            .browserDownloadUrl
    }
}

@MainActor
final class BetaFeedResolver {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct CachedBetaFeed {
        let url: String
        let fetchedAt: Date
    }

    private var cachedBetaFeed: CachedBetaFeed?
    private(set) var currentBetaFeedURL: String?
    private let ttl: TimeInterval
    private let now: () -> Date
    private let loadData: DataLoader

    init(
        ttl: TimeInterval = 15 * 60,
        now: @escaping () -> Date = Date.init,
        loadData: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.ttl = ttl
        self.now = now
        self.loadData = loadData
    }

    func fetchLatestBeta() async -> Bool {
        if let cached = cachedBetaFeed, now().timeIntervalSince(cached.fetchedAt) < ttl {
            currentBetaFeedURL = cached.url
            return true
        }

        guard let url = UpdatePolicy.betaReleasesEndpoint else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await loadData(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                Logfile.app.warning("[Updater] GitHub API rate limit hit (HTTP 403).")
                return currentBetaFeedURL != nil
            }
            if let downloadURL = try UpdatePolicy.extractBetaAppcastURL(from: data) {
                currentBetaFeedURL = downloadURL
                cachedBetaFeed = CachedBetaFeed(url: downloadURL, fetchedAt: now())
                return true
            }
        } catch {
            Logfile.app.warning("[Updater] Failed to fetch beta releases: \(error.localizedDescription)")
            return currentBetaFeedURL != nil
        }

        return false
    }
}
