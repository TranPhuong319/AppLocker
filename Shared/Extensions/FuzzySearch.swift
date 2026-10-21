//
//  FuzzySearch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

/// Lọc danh sách ứng dụng đã cài đặt theo từ khóa: ưu tiên tên bản địa, fallback tên gốc, bundleID hoặc đường dẫn
extension Sequence where Element == InstalledApp {
    func filter(matching searchText: String) -> [InstalledApp] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Array(self) }
        let tokens = trimmed.split(separator: " ")
        guard !tokens.isEmpty else { return Array(self) }

        return self.compactMap { app -> (app: InstalledApp, score: Int)? in
            var totalScore = 0
            for token in tokens {
                if app.name.localizedCaseInsensitiveCompare(String(token)) == .orderedSame {
                    totalScore += 100
                } else if app.name.localizedStandardContains(token) {
                    totalScore += 50
                } else if let orig = app.originalName, orig.localizedStandardContains(token) {
                    totalScore += 20
                } else if app.bundleID.localizedCaseInsensitiveContains(token) {
                    totalScore += 10
                } else if app.path.localizedCaseInsensitiveContains(token) {
                    totalScore += 5
                } else {
                    return nil
                }
            }
            return (app, totalScore)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
        .map { $0.app }
    }
}
