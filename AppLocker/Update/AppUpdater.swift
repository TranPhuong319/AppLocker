//
//  AppUpdater.swift
//  AppLocker
//
//  Created by Doe Phương on 26/8/25.
//

import Foundation
import Sparkle

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var betaFeedURL: String? // Lưu URL beta mới nhất lấy từ GitHub
    var useBeta: Bool = false

    func feedURLString(for updater: SPUUpdater) -> String? {
        if useBeta {
            return betaFeedURL
        } else {
            return nil // dùng feed URL trong plist (stable)
        }
    }
}

class AppUpdater: NSObject {
    static let shared = AppUpdater()

    private let delegate = UpdaterDelegate()
    let updaterController: SPUStandardUpdaterController

    private override init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Check update stable hoặc beta
    func checkForUpdates(useBeta: Bool) {
        delegate.useBeta = useBeta
        if useBeta {
            fetchLatestBeta { success in
                DispatchQueue.main.async {
                    self.updaterController.checkForUpdates(nil)
                }
            }
        } else {
            updaterController.checkForUpdates(nil)
        }
    }

    /// Lấy appcast beta mới nhất từ GitHub API
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

// MARK: - GitHub API Model
struct BetaGitHubRelease: Decodable {
    let tag_name: String
    let prerelease: Bool
    let assets: [BetaGitHubAsset]
}

struct BetaGitHubAsset: Decodable {
    let name: String
    let browser_download_url: String
}
