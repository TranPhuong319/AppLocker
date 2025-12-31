//
//  FuzzySearcch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

func fuzzyMatch(query: String, target: String) -> Bool {
    let q = query.normalized
    let t = target.normalized

    if t.contains(q) { return true }

    let tokens = q.split(separator: " ")
    return tokens.allSatisfy { t.contains($0) }
}

extension String {
    var normalized: String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
