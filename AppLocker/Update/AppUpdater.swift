//
//  AppUpdater.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import AppKit
import Foundation
import Sparkle

// MARK: - UpdaterDelegate (SINGLE INSTANCE, NO SINGLETON)
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {

    var betaFeedURL: String?
    var channel: Channel = .stable
    var downloadState: UpdateDownloadState = .notDownloaded

    // Feed URL override
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdatePolicy.feedURLString(channel: channel, betaFeedURL: betaFeedURL)
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
            self?.downloadState = .notDownloaded
            AppUpdater.shared.handleNoUpdateFound()
            NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if choice == .skip {
                self.downloadState = .notDownloaded
                AppUpdater.shared.handleNoUpdateFound()
                NotificationCenter.default.post(name: .appLockerPendingUpdateDidChange, object: nil)
            }
        }
    }
}

// MARK: - AppUpdater (OWNER OF DELEGATE)
@MainActor
final class AppUpdater: NSObject {

    static let shared = AppUpdater()

    let delegate: UpdaterDelegate
    let updaterController: SPUStandardUpdaterController
    private let betaFeedResolver = BetaFeedResolver()

    private override init() {
        let delegate = UpdaterDelegate()
        self.delegate = delegate

        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )

        super.init()
        #if DEBUG
        updaterController.updater.updateCheckInterval = 600
        #endif
        delegate.channel = UpdatePolicy.channel(
            from: UserDefaults.standard.string(forKey: "updateChannel")
        )
        observeUserDefaults()

        if delegate.channel == .beta {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.fetchLatestBeta()
                self.updaterController.startUpdater()
            }
        } else {
            updaterController.startUpdater()
        }
    }

    // MARK: - Channel sync (SOURCE OF TRUTH = UserDefaults)

    private func syncChannelFromDefaults() {
        let saved = UserDefaults.standard.string(forKey: "updateChannel")
        let newChannel = UpdatePolicy.channel(from: saved)
        guard newChannel != delegate.channel else { return }
        delegate.channel = newChannel
        if newChannel == .beta, delegate.betaFeedURL == nil {
            Task { _ = await fetchLatestBeta() }
        }
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

    // MARK: - Update checks

    func checkForUpdates() {
        if delegate.channel == .beta {
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.fetchLatestBeta()
                self.updaterController.checkForUpdates(nil)
            }
        } else {
            updaterController.checkForUpdates(nil)
        }
    }

    // MARK: - Beta appcast fetch

    private func fetchLatestBeta() async -> Bool {
        let previousFallback = betaFeedResolver.hasNoActiveBetaRelease
        let success = await betaFeedResolver.fetchLatestBeta()
        delegate.betaFeedURL = betaFeedResolver.currentBetaFeedURL
        if betaFeedResolver.hasNoActiveBetaRelease != previousFallback {
            NotificationCenter.default.post(name: .appLockerBetaFallbackDidChange, object: nil)
        }
        return success
    }

    // MARK: - Exposed state

    var downloadState: UpdateDownloadState { delegate.downloadState }
    var isBetaUsingStableFallback: Bool {
        delegate.channel == .beta && betaFeedResolver.hasNoActiveBetaRelease
    }

    private(set) var availableUpdateVersion: String?
    var hasAvailableUpdate: Bool { availableUpdateVersion != nil }

    func handleFoundUpdate(_ item: SUAppcastItem) {
        let displayVer = item.displayVersionString
        let buildVer = item.versionString
        self.availableUpdateVersion = (displayVer != buildVer) ? "\(displayVer) (\(buildVer))" : displayVer
    }

    func handleNoUpdateFound() {
        self.availableUpdateVersion = nil
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

extension Notification.Name {
    static let appLockerBetaFallbackDidChange = Notification.Name("appLockerBetaFallbackDidChange")
}
