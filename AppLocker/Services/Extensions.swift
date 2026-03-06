//
//  Extensions.swift
//  AppLocker
//
//  Created by Doe Phương on 11/1/26.
//

import Foundation

extension String {
    var alNormalized: String {
        return self.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
