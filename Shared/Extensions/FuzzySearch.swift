//
//  FuzzySearch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

/// Lọc danh sách ứng dụng đã cài đặt theo từ khóa (khớp trên tên, bundleID hoặc đường dẫn)
extension Sequence where Element == InstalledApp {
    func filter(matching searchText: String) -> [InstalledApp] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(self) }
        let tokens = trimmed.split(separator: " ")
        guard !tokens.isEmpty else { return Array(self) }

        return self.filter { app in
            tokens.allSatisfy { token in
                app.name.localizedCaseInsensitiveContains(token)
                    || app.bundleID.localizedCaseInsensitiveContains(token)
                    || app.path.localizedCaseInsensitiveContains(token)
            }
        }
    }
}
