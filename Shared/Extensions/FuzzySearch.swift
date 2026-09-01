//
//  FuzzySearch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

func fuzzyMatch<S: StringProtocol>(_ tokens: some Sequence<S>, in target: String) -> Bool {
    let normalizedTarget = target.normalized
    return tokens.allSatisfy { normalizedTarget.contains($0) }
}

extension String {
    var normalized: String {
        self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
