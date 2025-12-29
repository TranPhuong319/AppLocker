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

    /// Execute closure under lock and return its value.
    @inline(__always)
    func sync<T>(_ closure: () -> T) -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return closure()
    }

    /// Execute closure under lock for quick fire-and-forget writes.
    @inline(__always)
    func perform(_ closure: () -> Void) {
        os_unfair_lock_lock(&_lock)
        closure()
        os_unfair_lock_unlock(&_lock)
    }
}
