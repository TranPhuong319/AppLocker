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
    case stable
    case beta
}

enum UpdateDownloadState {
    case notDownloaded
    case downloaded
}

// MARK: - Bridge

protocol AppUpdaterBridgeDelegate: AnyObject {
    func didFindUpdate(_ item: SUAppcastItem)
    func didNotFindUpdate()
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

    weak var bridgeDelegate: AppUpdaterBridgeDelegate?

    // Feed URL override
    func feedURLString(for updater: SPUUpdater) -> String? {
        channel == .beta ? betaFeedURL : nil
    }

    // MARK: Sparkle callbacks

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.downloadState = .notDownloaded
            self.bridgeDelegate?.didFindUpdate(item)
        }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.downloadState = .downloaded
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async {
            self.bridgeDelegate?.didNotFindUpdate()
        }
    }
}

// MARK: - AppUpdater (OWNER OF DELEGATE)

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

    // MARK: - Bridge

    func setBridgeDelegate(_ bridgeDelegate: AppUpdaterBridgeDelegate) {
        delegate.bridgeDelegate = bridgeDelegate
    }

    // MARK: - Channel sync (SOURCE OF TRUTH = UserDefaults)

    private func syncChannelFromDefaults() {
        let saved = UserDefaults.standard.string(forKey: "updateChannel") ?? "Stable"
        delegate.channel = (saved == "Beta") ? .beta : .stable
    }

    private func observeUserDefaults() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func userDefaultsDidChange() {
        syncChannelFromDefaults()
    }

    // MARK: - Auto check

    func startAutoCheck(interval: TimeInterval = 6 * 60 * 60) {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.silentCheckForUpdates()
        }
        updateTimer?.tolerance = 10
    }

    func startTestAutoCheck() {
#if DEBUG
        startAutoCheck(interval: 300)
#else
        startAutoCheck()
#endif
    }

    // MARK: - Update checks

    func silentCheckForUpdates() {
        if delegate.channel == .beta {
            fetchLatestBeta { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updaterController.updater.checkForUpdateInformation()
                }
            }
        } else {
            updaterController.updater.checkForUpdateInformation()
        }
    }

    func manualCheckForUpdates() {
        if delegate.channel == .beta {
            fetchLatestBeta { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updaterController.checkForUpdates(nil)
                }
            }
        } else {
            updaterController.checkForUpdates(nil)
        }
    }

    // MARK: - Beta appcast fetch

    private func fetchLatestBeta(completion: @escaping (Bool) -> Void) {
        let url = URL(string: "https://api.github.com/repos/TranPhuong319/AppLocker/releases")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data, error == nil else {
                completion(false)
                return
            }

            do {
                let releases = try JSONDecoder().decode([BetaGitHubRelease].self, from: data)
                if let beta = releases.first(where: { $0.isPrerelease }),
                   let appcast = beta.assets.first(where: { $0.name == "appcast.xml" }) {
                    self?.delegate.betaFeedURL = appcast.browserDownloadUrl
                    completion(true)
                } else {
                    completion(false)
                }
            } catch {
                completion(false)
            }
        }.resume()
    }

    // MARK: - Exposed state (READ ONLY)

    var currentChannel: Channel { delegate.channel }
    var downloadState: UpdateDownloadState { delegate.downloadState }
}

// MARK: - GitHub API Models

struct BetaGitHubRelease: Decodable {
    let isPrerelease: Bool
    let assets: [BetaGitHubAsset]

    enum CodingKeys: String, CodingKey {
        case isPrerelease = "prerelease"
        case assets
    }
}

struct BetaGitHubAsset: Decodable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}
