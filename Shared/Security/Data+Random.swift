//
//  Data+Random.swift
//  AppLocker
//
//  Created by Doe Phương on 27/1/26.
//

import Foundation

extension Data {
    static func random(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
}
