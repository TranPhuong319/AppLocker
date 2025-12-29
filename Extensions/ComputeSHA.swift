//
//  ComputeSHA.swift
//  AppLocker
//
//  Created by Doe Phương on 27/12/25.
//

import Foundation
import CryptoKit

func computeSHA(forPath path: String) -> String? {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var hasher = SHA256()

    let bufferSize = 256 * 1024
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }

    while true {
        if true {
            let bytesRead = read(fd, buffer, bufferSize)
            if bytesRead < 0 { return nil }
            if bytesRead == 0 { break }

            let rawBuffer = UnsafeRawBufferPointer(start: buffer, count: bytesRead)
            hasher.update(bufferPointer: rawBuffer)
        }
    }

    let digest = hasher.finalize()

    return fastHex(from: digest)
}

func fastHex(from digest: SHA256.Digest) -> String {
    let hexAlphabet = Array("0123456789abcdef".utf16)

    var hexChars = [UInt16]()
    hexChars.reserveCapacity(64)

    for byte in digest {
        hexChars.append(hexAlphabet[Int(byte >> 4)])
        hexChars.append(hexAlphabet[Int(byte & 0x0f)])
    }

    return String(utf16CodeUnits: hexChars, count: hexChars.count)
}
