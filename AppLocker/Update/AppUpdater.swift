//
//  AppUpdater.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import Foundation
import Sparkle

protocol AppUpdaterBridgeDelegate: AnyObject {
    func didFindUpdate(_ item: SUAppcastItem)
    func didNotFindUpdate()
}

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var betaFeedURL: String?
    var useBeta: Bool = false
    weak var bridgeDelegate: AppUpdaterBridgeDelegate?

    // feed URL override
    func feedURLString(for updater: SPUUpdater) -> String? {
        if useBeta {
            return betaFeedURL
        } else {
            return nil
        }
    }

    // Callback khi có update hợp lệ
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        bridgeDelegate?.didFindUpdate(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        bridgeDelegate?.didNotFindUpdate()
    }
}

class AppUpdater: NSObject {
    static let shared = AppUpdater()
    private var updateTimer: Timer?

    private let delegate = UpdaterDelegate()
    let updaterController: SPUStandardUpdaterController

    private override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil // AppDelegate sẽ handle riêng cho manual check
        )
        super.init()
    }

    // Cho AppDelegate đăng ký nhận sự kiện
    func setBridgeDelegate(_ bridgeDelegate: AppUpdaterBridgeDelegate) {
        delegate.bridgeDelegate = bridgeDelegate
    }

    func startAutoCheck(interval: TimeInterval = 6*60*60) {
        updateTimer?.invalidate()
        DispatchQueue.main.async { [self] in
            updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [self] _ in
                let savedChannel = UserDefaults.standard.string(forKey: "updateChannel") ?? "Stable"
                let useBeta = (savedChannel == "Beta")
                silentCheckForUpdates(useBeta: useBeta)
                Logfile.core.info("Run silent check update")
            }
        }
        updateTimer?.tolerance = 10
    }

    func startTestAutoCheck() {
        #if DEBUG
            startAutoCheck(interval: 600)
        #else
            startAutoCheck()
        #endif
    }

    // Silent check
    func silentCheckForUpdates(useBeta: Bool) {
        delegate.useBeta = useBeta
        if useBeta {
            fetchLatestBeta { _ in
                DispatchQueue.main.async {
                    self.updaterController.updater.checkForUpdateInformation()
                }
            }
        } else {
            updaterController.updater.checkForUpdateInformation()
        }
    }
        
    // Manual check
    func manualCheckForUpdates(useBeta: Bool) {
        delegate.useBeta = useBeta
        if useBeta {
            fetchLatestBeta { _ in
                DispatchQueue.main.async {
                    self.updaterController.checkForUpdates(nil)
                }
            }
        } else {
            DispatchQueue.main.async {
                self.updaterController.checkForUpdates(nil)
            }
        }
    }

    // GitHub API để lấy appcast beta
    private func fetchLatestBeta(completion: @escaping (Bool) -> Void) {
        let url = URL(string: "https://api.github.com/repos/TranPhuong319/AppLocker/releases")!
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                Logfile.core.error("GitHub API error: \(String(describing: error), privacy: .public)")
                completion(false)
                return
            }

            do {
                let releases = try JSONDecoder().decode([BetaGitHubRelease].self, from: data)
                if let latestBeta = releases.first(where: { $0.prerelease }),
                   let appcast = latestBeta.assets.first(where: { $0.name == "appcast.xml" }) {
                    self.delegate.betaFeedURL = appcast.browser_download_url
                    completion(true)
                } else {
                    Logfile.core.info("No beta release found")
                    completion(false)
                }
            } catch {
                Logfile.core.error("Decode error: \(error, privacy: .public)")
                completion(false)
            }
        }.resume()
    }
}

// MARK: - GitHub API Models
struct BetaGitHubRelease: Decodable {
    let tag_name: String
    let prerelease: Bool
    let assets: [BetaGitHubAsset]
}

struct BetaGitHubAsset: Decodable {
    let name: String
    let browser_download_url: String
}
