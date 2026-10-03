//
//  FuzzySearch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

func fuzzyMatch<S: StringProtocol>(_ tokens: some Sequence<S>, in target: String) -> Bool {
    tokens.allSatisfy { target.localizedCaseInsensitiveContains($0) }
}
