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
        closure()
        os_unfair_lock_unlock(&_lock)
    }

    @inline(__always)
    func performThrowing(_ closure: () throws -> Void) throws {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        try closure()
    }

    // --- try variants (không block)
    @inline(__always)
    func trySync<T>(default defaultValue: T, _ closure: () -> T) -> T {
        if os_unfair_lock_trylock(&_lock) {
            defer { os_unfair_lock_unlock(&_lock) }
            return closure()
        }
        return defaultValue
    }

    @inline(__always)
    func tryPerform(default: Bool = false, _ closure: () -> Void) -> Bool {
        if os_unfair_lock_trylock(&_lock) {
            closure()
            os_unfair_lock_unlock(&_lock)
            return true
        }
        return false
    }
}
