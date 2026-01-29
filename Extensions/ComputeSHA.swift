//
//  ComputeSHA.swift
//  AppLocker
//
//  Created by Doe Phương on 27/12/25.
//

import CryptoKit
import Foundation

// SHARED CONSTANT: Both App & ES must read exactly the same amount to produce the same Hash.
// 5MB is a safe balance: Harder to bypass than 1MB, but fast enough for ES (<50ms).
public let SHA_READ_LIMIT = 5 * 1024 * 1024

func computeSHA(forPath path: String) -> String? {
    // Default to SHA_READ_LIMIT for consistency across the entire system
    return computeSHA(forPath: path, maxBytes: SHA_READ_LIMIT)
}

func computeSHA(forPath path: String, maxBytes: Int) -> String? {
    // Check file size first - skip if too large to avoid ES timeout
    var fileStat = stat()
    guard stat(path, &fileStat) == 0 else { return nil }

    let fileDescriptor = open(path, O_RDONLY)
    guard fileDescriptor >= 0 else { return nil }
    defer { close(fileDescriptor) }

    var hasher = SHA256()

    let bufferSize = 256 * 1024
    let buffer = UnsafeMutableRawPointer.allocate(
        byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }

    // Optimization limit
    let limit = maxBytes
    var totalRead = 0

    while totalRead < limit {
        // Calculate remaining bytes to reach limit
        let remaining = limit - totalRead
        let bytesToRead = min(bufferSize, remaining)

        let bytesRead = read(fileDescriptor, buffer, bytesToRead)
        if bytesRead < 0 { return nil }
        if bytesRead == 0 { break }

        let rawBuffer = UnsafeRawBufferPointer(start: buffer, count: bytesRead)
        hasher.update(bufferPointer: rawBuffer)

        totalRead += bytesRead
    }

    let sha256Digest = hasher.finalize()

    return fastHex(from: sha256Digest)
}

func fastHex(from digest: SHA256.Digest) -> String {
    let hexadecimalAlphabet = Array("0123456789abcdef".utf16)

    var hexCharacters = [UInt16]()
    hexCharacters.reserveCapacity(64)

    for digestByte in digest {
        hexCharacters.append(hexadecimalAlphabet[Int(digestByte >> 4)])
        hexCharacters.append(hexadecimalAlphabet[Int(digestByte & 0x0f)])
    }

    return String(utf16CodeUnits: hexCharacters, count: hexCharacters.count)
}
