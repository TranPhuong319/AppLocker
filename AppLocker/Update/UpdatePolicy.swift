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

enum UpdatePolicy {
    static let betaReleasesEndpoint = URL(string: "https://api.github.com/repos/TranPhuong319/AppLocker/releases")

    static func channel(from rawValue: String?) -> Channel {
        rawValue == "Beta" ? .beta : .stable
    }

    static func feedURLString(channel: Channel, betaFeedURL: String?) -> String? {
        channel == .beta ? betaFeedURL : nil
    }

    static func effectiveNotificationChannel(selectedChannel: Channel, betaFeedURL: String?) -> Channel {
        selectedChannel == .beta && betaFeedURL != nil ? .beta : .stable
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
    private(set) var hasNoActiveBetaRelease = false
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
            hasNoActiveBetaRelease = false
            return true
        }

        guard let url = UpdatePolicy.betaReleasesEndpoint else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await loadData(request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 403 {
                    Logfile.app.warning("[Updater] GitHub API rate limit hit (HTTP 403).")
                    return currentBetaFeedURL != nil
                }
                guard (200..<300).contains(http.statusCode) else {
                    return currentBetaFeedURL != nil
                }
            }
            if let downloadURL = try UpdatePolicy.extractBetaAppcastURL(from: data) {
                currentBetaFeedURL = downloadURL
                cachedBetaFeed = CachedBetaFeed(url: downloadURL, fetchedAt: now())
                hasNoActiveBetaRelease = false
                return true
            }
            currentBetaFeedURL = nil
            cachedBetaFeed = nil
            hasNoActiveBetaRelease = true
        } catch {
            Logfile.app.warning("[Updater] Failed to fetch beta releases: \(error.localizedDescription)")
            return currentBetaFeedURL != nil
        }

        return false
    }
}
