//
//  FuzzySearch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

func fuzzyMatch(query: String, target: String) -> Bool {
    let normalizedTarget = target.normalized
    return query.normalized.split(separator: " ").allSatisfy { normalizedTarget.contains($0) }
}

extension String {
    var normalized: String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
