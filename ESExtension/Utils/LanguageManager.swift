//
//  LanguageManager.swift
//  ESExtension
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

extension ESManager {
    // Force the extension process to use a specific language.
    @objc func updateLanguage(to code: String) {
        guard isCurrentConnectionAuthenticated() else {
            Logfile.es.error("Unauthorized call to updateLanguage")
            return
        }
        stateLock.perform {
            self.currentLanguage = code
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            Logfile.es.log("ES Process language forced to: \(code, privacy: .public)")
        }
    }

    // Read the current language in a thread-safe way.
    func getCurrentLanguage() -> String {
        return stateLock.sync { self.currentLanguage }
    }
}
