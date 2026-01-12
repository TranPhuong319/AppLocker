//
//  FSEventsMonitoringService.swift
//  AppLocker
//
//  Created by Doe Phương on 12/1/26.
//

import Foundation

protocol FSEventsDelegate: AnyObject {
    func fileSystemChanged(at paths: [String])
}

class FSEventsMonitoringService {
    private var stream: FSEventStreamRef?
    weak var delegate: FSEventsDelegate?
    private let pathsToWatch: [String]

    init(paths: [String]) {
        self.pathsToWatch = paths
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = {
            (_, clientCallBackInfo, numEvents, eventPaths, _, _) in
            let watcher = Unmanaged<FSEventsMonitoringService>.fromOpaque(clientCallBackInfo!)
                .takeUnretainedValue()
            let paths = UnsafeBufferPointer(
                start: eventPaths.assumingMemoryBound(to: UnsafePointer<Int8>.self),
                count: numEvents)

            var changedPaths: [String] = []
            for i in 0..<numEvents {
                let path = String(cString: paths[i])
                changedPaths.append(path)
            }

            watcher.delegate?.fileSystemChanged(at: changedPaths)
        }

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // Latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        guard let stream = stream else { return }

        let queue = DispatchQueue(label: "com.TranPhuong319.AppLocker.fsevents", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
