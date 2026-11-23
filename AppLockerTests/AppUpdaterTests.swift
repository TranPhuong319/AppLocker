//
//  AppUpdaterTests.swift
//  AppLockerTests
//
//  Created by Doe Phương on 18/11/26.
//

import Foundation
import os
import Testing

@Suite("AppUpdater Channel, Beta Feed Cache & Manual Check Policy Tests")
struct AppUpdaterTests {

    private func makeBetaPayload(appcastURL: String) -> Data {
        let json = """
        [
          {
            "prerelease": true,
            "assets": [{ "name": "appcast.xml", "browser_download_url": "\(appcastURL)" }]
          }
        ]
        """
        return Data(json.utf8)
    }

    private func makeResponse(for request: URLRequest, statusCode: Int) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        )
    }

    @Test("Channel parsing and Sparkle feedURLString selection")
    func channelAndFeedURLSelection() {
        #expect(UpdatePolicy.channel(from: "Beta") == .beta)
        #expect(UpdatePolicy.channel(from: "Stable") == .stable)
        #expect(UpdatePolicy.channel(from: nil) == .stable)
        #expect(UpdatePolicy.channel(from: "Other") == .stable)

        let betaURL = "https://github.com/TranPhuong319/AppLocker/releases/download/v2.0-beta/appcast.xml"
        #expect(UpdatePolicy.feedURLString(channel: .stable, betaFeedURL: betaURL) == nil)
        #expect(UpdatePolicy.feedURLString(channel: .beta, betaFeedURL: betaURL) == betaURL)
        #expect(UpdatePolicy.feedURLString(channel: .beta, betaFeedURL: nil) == nil)

        #expect(UpdatePolicy.effectiveNotificationChannel(selectedChannel: .stable, betaFeedURL: betaURL) == .stable)
        #expect(UpdatePolicy.effectiveNotificationChannel(selectedChannel: .beta, betaFeedURL: betaURL) == .beta)
        #expect(UpdatePolicy.effectiveNotificationChannel(selectedChannel: .beta, betaFeedURL: nil) == .stable)
    }

    @Test("Extracts appcast.xml URL from first GitHub prerelease only")
    func extractBetaAppcastURL() throws {
        let json = """
        [
          {
            "prerelease": false,
            "assets": [
              { "name": "appcast.xml", "browser_download_url": "https://example.com/stable-appcast.xml" }
            ]
          },
          {
            "prerelease": true,
            "assets": [
              { "name": "AppLocker.dmg", "browser_download_url": "https://example.com/AppLocker.dmg" },
              { "name": "appcast.xml", "browser_download_url": "https://example.com/beta-appcast.xml" }
            ]
          }
        ]
        """
        let extracted = try UpdatePolicy.extractBetaAppcastURL(from: Data(json.utf8))
        #expect(extracted == "https://example.com/beta-appcast.xml")

        let noPrereleaseJSON = """
        [
          {
            "prerelease": false,
            "assets": [
              { "name": "appcast.xml", "browser_download_url": "https://example.com/stable-appcast.xml" }
            ]
          }
        ]
        """
        #expect(try UpdatePolicy.extractBetaAppcastURL(from: Data(noPrereleaseJSON.utf8)) == nil)
    }

    @Test("BetaFeedResolver caches feed within 15-minute TTL and refreshes after expiration")
    @MainActor
    func betaFeedCachingAndTTLExpiration() async {
        let nowBox = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
        let fetchCount = OSAllocatedUnfairLock(initialState: 0)
        let firstURL = "https://example.com/beta-1/appcast.xml"
        let secondURL = "https://example.com/beta-2/appcast.xml"

        let resolver = BetaFeedResolver(
            ttl: 15 * 60,
            now: { nowBox.withLock { $0 } },
            loadData: { request in
                let count = fetchCount.withLock { value in
                    value += 1
                    return value
                }
                let targetURL = count == 1 ? firstURL : secondURL
                return (makeBetaPayload(appcastURL: targetURL), try makeResponse(for: request, statusCode: 200))
            }
        )

        #expect(await resolver.fetchLatestBeta() == true)
        #expect(resolver.currentBetaFeedURL == firstURL)
        #expect(fetchCount.withLock { $0 } == 1)

        nowBox.withLock { $0 = Date(timeIntervalSince1970: 1_000 + 10 * 60) }
        #expect(await resolver.fetchLatestBeta() == true)
        #expect(resolver.currentBetaFeedURL == firstURL)
        #expect(fetchCount.withLock { $0 } == 1)

        nowBox.withLock { $0 = Date(timeIntervalSince1970: 1_000 + 16 * 60) }
        #expect(await resolver.fetchLatestBeta() == true)
        #expect(resolver.currentBetaFeedURL == secondURL)
        #expect(fetchCount.withLock { $0 } == 2)
    }

    @Test("BetaFeedResolver returns false on HTTP 403 when no cache exists")
    @MainActor
    func betaFeedRateLimitWithoutCache() async {
        let resolver = BetaFeedResolver(
            ttl: 15 * 60,
            now: { Date(timeIntervalSince1970: 2_000) },
            loadData: { request in
                (Data(), try makeResponse(for: request, statusCode: 403))
            }
        )

        #expect(await resolver.fetchLatestBeta() == false)
        #expect(resolver.currentBetaFeedURL == nil)
        #expect(resolver.hasNoActiveBetaRelease == false)
    }

    @Test("BetaFeedResolver keeps stale cached URL when refresh fails offline")
    @MainActor
    func betaFeedStaleCacheFallbackOnNetworkError() async {
        let nowBox = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 2_000))
        let callIndex = OSAllocatedUnfairLock(initialState: 0)
        let cachedURL = "https://example.com/cached.xml"

        let resolver = BetaFeedResolver(
            ttl: 15 * 60,
            now: { nowBox.withLock { $0 } },
            loadData: { request in
                let idx = callIndex.withLock { val in
                    val += 1
                    return val
                }
                if idx == 1 {
                    return (makeBetaPayload(appcastURL: cachedURL), try makeResponse(for: request, statusCode: 200))
                }
                throw URLError(.notConnectedToInternet)
            }
        )

        #expect(await resolver.fetchLatestBeta() == true)
        nowBox.withLock { $0 = Date(timeIntervalSince1970: 2_000 + 20 * 60) }
        #expect(await resolver.fetchLatestBeta() == true)
        #expect(resolver.currentBetaFeedURL == cachedURL)
    }

    @Test("BetaFeedResolver clears cached URL when prereleases are removed so it falls back to Stable")
    @MainActor
    func betaFeedClearsStaleURLWhenPrereleaseRemoved() async {
        let nowBox = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 3_000))
        let callIndex = OSAllocatedUnfairLock(initialState: 0)

        let resolver = BetaFeedResolver(
            ttl: 15 * 60,
            now: { nowBox.withLock { $0 } },
            loadData: { request in
                let idx = callIndex.withLock { val in
                    val += 1
                    return val
                }
                let payload = idx == 1
                    ? self.makeBetaPayload(appcastURL: "https://example.com/alpha/appcast.xml")
                    : Data(#"[{"prerelease": false, "assets": []}]"#.utf8)
                return (payload, try self.makeResponse(for: request, statusCode: 200))
            }
        )

        #expect(await resolver.fetchLatestBeta() == true)
        #expect(resolver.currentBetaFeedURL == "https://example.com/alpha/appcast.xml")
        #expect(resolver.hasNoActiveBetaRelease == false)

        nowBox.withLock { $0 = Date(timeIntervalSince1970: 3_000 + 20 * 60) }
        #expect(await resolver.fetchLatestBeta() == false)
        #expect(resolver.currentBetaFeedURL == nil)
        #expect(resolver.hasNoActiveBetaRelease == true)
    }
}
