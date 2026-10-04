//
//  FuzzySearch.swift
//  AppLocker
//
//  Created by Doe Phương on 31/12/25.
//

import Foundation

/// Determines whether all tokens in the provided sequence are contained within the target string.
/// - Parameters:
///   - tokens: A sequence of string tokens to match.
///   - target: The target string being searched.
/// - Returns: `true` if every token in `tokens` is contained in `target` ignoring case; otherwise `false`.
func fuzzyMatch<S: StringProtocol>(_ tokens: some Sequence<S>, in target: String) -> Bool {
    tokens.allSatisfy { target.localizedCaseInsensitiveContains($0) }
}
