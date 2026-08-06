//
//  FastLock.swift
//  AppLocker
//
//  Created by Doe Phương on 29/12/25.
//

import Foundation
import os

final class FastLock {
    private var _lock = os_unfair_lock()

    @inline(__always)
    func sync<T>(_ closure: () -> T) -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return closure()
    }

    @inline(__always)
    func perform(_ closure: () -> Void) {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        closure()
    }
}
