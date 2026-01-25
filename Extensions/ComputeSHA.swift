//
//  ComputeSHA.swift
//  AppLocker
//
//  Created by Doe Phương on 27/12/25.
//

import CryptoKit
import Foundation

func computeSHA(forPath path: String) -> String? {
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

    // Optimization: Only hash first 1MB to avoid ES Timeouts
    let maxReadSize = 1 * 1024 * 1024
    var totalRead = 0

    while totalRead < maxReadSize {
        // Calculate remaining bytes to reach 1MB limit
        let remaining = maxReadSize - totalRead
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
