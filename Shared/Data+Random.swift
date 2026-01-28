//
//  Data+Random.swift
//  AppLocker
//
//  Created by Doe Phương on 27/1/26.
//

import Foundation

extension Data {
    static func random(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        return data
    }
}
