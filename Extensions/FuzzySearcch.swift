//
//  FuzzySearcch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

func fuzzyMatch(query: String, target: String) -> Bool {
    let normalizedQuery = query.normalized
    let normalizedTarget = target.normalized

    if normalizedTarget.contains(normalizedQuery) { return true }

    let queryTokens = normalizedQuery.split(separator: " ")
    return queryTokens.allSatisfy { normalizedTarget.contains($0) }
}

extension String {
    var normalized: String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
