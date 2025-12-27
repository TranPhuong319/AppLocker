//
//  ComputeSHA.swift
//  AppLocker
//
//  Created by Doe Phương on 27/12/25.
//

import Foundation
import CryptoKit

func computeSHA(forPath path: String) -> String? {
    // EN: 1) Open file via POSIX call to avoid FileHandle overhead.
    // VI: 1) Mở file bằng POSIX để tránh overhead của FileHandle.
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    var hasher = SHA256()

    // EN: 2) 256KB buffer tuned for SSD/NVMe throughput.
    // VI: 2) Bộ đệm 256KB tối ưu cho SSD/NVMe.
    let bufferSize = 256 * 1024
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }

    while true {
        if true {
            let bytesRead = read(fd, buffer, bufferSize)
            if bytesRead < 0 { return nil } // EN: read error / VI: Lỗi đọc file
            if bytesRead == 0 { break }     // EN: EOF / VI: Hết file

            let rawBuffer = UnsafeRawBufferPointer(start: buffer, count: bytesRead)
            hasher.update(bufferPointer: rawBuffer)
        }
    }

    let digest = hasher.finalize()

    // EN: 3) Convert digest to hex using a fast lookup.
    // VI: 3) Chuyển digest sang hex bằng tra cứu nhanh.
    return fastHex(from: digest)
}

// EN: Convert SHA-256 digest to a lowercase hex string efficiently.
// VI: Chuyển digest SHA-256 sang chuỗi hex chữ thường hiệu quả.
func fastHex(from digest: SHA256.Digest) -> String {
    // EN: Lookup table using UTF-16 code units to avoid encoding overhead.
    // VI: Bảng tra cứu dùng mã UTF-16 để tránh chi phí mã hóa.
    let hexAlphabet = Array("0123456789abcdef".utf16)

    // EN: SHA-256 produces 32 bytes; hex string is 64 characters.
    // VI: SHA-256 trả về 32 byte; chuỗi hex có 64 ký tự.
    var hexChars = [UInt16]()
    hexChars.reserveCapacity(64)

    for byte in digest {
        // EN: High nibble lookup.
        // VI: Tra cứu nibble cao.
        hexChars.append(hexAlphabet[Int(byte >> 4)])
        // EN: Low nibble lookup.
        // VI: Tra cứu nibble thấp.
        hexChars.append(hexAlphabet[Int(byte & 0x0f)])
    }

    return String(utf16CodeUnits: hexChars, count: hexChars.count)
}
