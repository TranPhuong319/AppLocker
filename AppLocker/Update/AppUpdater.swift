//
//  AppUpdater.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import Foundation
import Sparkle

// MARK: - Enums

enum Channel {
    case stable, beta
}

enum UpdateDownloadState {
    case notDownloaded, downloaded
}

// MARK: - Notification Action

enum UpdateNotificationAction {
    static let more = "UPDATE_MORE"
}

// MARK: - UpdaterDelegate (SINGLE INSTANCE, NO SINGLETON)
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {

    var betaFeedURL: String?
    var channel: Channel = .stable
    var downloadState: UpdateDownloadState = .notDownloaded

    // Feed URL override
    func feedURLString(for updater: SPUUpdater) -> String? {
        channel == .beta ? betaFeedURL : nil
    }

    // MARK: Sparkle callbacks

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.downloadState = .notDownloaded
            AppUpdater.shared.handleFoundUpdate(item)
            NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: item)
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.downloadState = .downloaded
            NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: item)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            AppUpdater.shared.handleNoUpdateFound()
            NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)
        }
    }
}

// MARK: - AppUpdater (OWNER OF DELEGATE)
@MainActor
final class AppUpdater: NSObject {

    static let shared = AppUpdater()

    private var updateTimer: Timer?
    let delegate: UpdaterDelegate
    let updaterController: SPUStandardUpdaterController

    private override init() {
        let delegate = UpdaterDelegate()
        self.delegate = delegate

        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )

        super.init()
        syncChannelFromDefaults()
        observeUserDefaults()
    }

    // MARK: - Channel sync (SOURCE OF TRUTH = UserDefaults)

    private func syncChannelFromDefaults() {
        let saved = UserDefaults.standard.string(forKey: "updateChannel") ?? "Stable"
        delegate.channel = (saved == "Beta") ? .beta : .stable
    }

    private func observeUserDefaults() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncChannelFromDefaults()
            }
        }
    }

    // MARK: - Auto check

    func startAutoCheck(interval: TimeInterval = 6 * 60 * 60) {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.silentCheckForUpdates()
            }
        }
        updateTimer?.tolerance = 10
    }

    func startTestAutoCheck(interval: TimeInterval? = nil) {
        #if DEBUG
            startAutoCheck(interval: interval ?? 60)
        #else
            if delegate.channel == .beta {
                Task { _ = await fetchLatestBeta() }
            }
        #endif
    }

    // MARK: - Update checks

    func silentCheckForUpdates() {
        let updater = updaterController.updater
        guard updater.automaticallyChecksForUpdates, !updater.sessionInProgress else { return }

        let triggerCheck = { [weak self] in
            self?.guardedCheck { updater in
                if updater.automaticallyDownloadsUpdates {
                    updater.checkForUpdatesInBackground()
                } else {
                    updater.checkForUpdateInformation()
                }
            }
        }

        if delegate.channel == .beta {
            Task { @MainActor [weak self] in
                guard let self, await self.fetchLatestBeta() else { return }
                triggerCheck()
            }
        } else {
            triggerCheck()
        }
    }

    private func guardedCheck(_ block: (SPUUpdater) -> Void) {
        let updater = updaterController.updater
        guard !updater.sessionInProgress else { return }
        block(updater)
    }

    func checkForUpdates() {
        guardedCheck { [weak self] _ in
            guard let self else { return }
            if self.delegate.channel == .beta {
                Task { @MainActor [weak self] in
                    guard let self, await self.fetchLatestBeta() else { return }
                    self.updaterController.checkForUpdates(nil)
                }
            } else {
                self.updaterController.checkForUpdates(nil)
            }
        }
    }

#if DEBUG
    func debugForceCheckIfPossible() {
        let updater = updaterController.updater
        guard !updater.sessionInProgress else { return }
        if updater.automaticallyDownloadsUpdates {
            updater.checkForUpdatesInBackground()
        } else {
            updater.checkForUpdateInformation()
        }
    }
#endif

    // MARK: - Beta appcast fetch

    private struct CachedBetaFeed {
        let url: String
        let fetchedAt: Date
    }
    private var cachedBetaFeed: CachedBetaFeed?
    private let betaFeedTTL: TimeInterval = 15 * 60

    private func fetchLatestBeta() async -> Bool {
        if let cached = cachedBetaFeed, Date().timeIntervalSince(cached.fetchedAt) < betaFeedTTL {
            self.delegate.betaFeedURL = cached.url
            return true
        }

        guard let url = URL(string: "https://api.github.com/repos/TranPhuong319/AppLocker/releases") else {
            return false
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                Logfile.app.warning("[Updater] GitHub API rate limit hit (HTTP 403).")
                return delegate.betaFeedURL != nil
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let releases = try decoder.decode([BetaGitHubRelease].self, from: data)
            if let beta = releases.first(where: { $0.prerelease }),
               let appcast = beta.assets.first(where: { $0.name == "appcast.xml" }) {
                let downloadUrl = appcast.browserDownloadUrl
                self.delegate.betaFeedURL = downloadUrl
                self.cachedBetaFeed = CachedBetaFeed(url: downloadUrl, fetchedAt: Date())
                return true
            }
        } catch {
            Logfile.app.warning("[Updater] Failed to fetch beta releases: \(error.localizedDescription)")
            return delegate.betaFeedURL != nil
        }
        return false
    }

    // MARK: - Exposed state

    var currentChannel: Channel { delegate.channel }
    var downloadState: UpdateDownloadState { delegate.downloadState }

    private(set) var availableUpdateVersion: String?
    var hasAvailableUpdate: Bool { availableUpdateVersion != nil }

    func handleFoundUpdate(_ item: SUAppcastItem) {
        let displayVer = item.displayVersionString
        let buildVer = item.versionString
        self.availableUpdateVersion = (displayVer != buildVer) ? "\(displayVer) (\(buildVer))" : displayVer
        NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)
    }

    func handleNoUpdateFound() {
        self.availableUpdateVersion = nil
        NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }
}

// MARK: - GitHub API Models

struct BetaGitHubRelease: Decodable {
    let prerelease: Bool
    let assets: [BetaGitHubAsset]
}

struct BetaGitHubAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
}
