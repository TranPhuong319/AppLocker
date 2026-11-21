//
//  AppDirectoryPolicy.swift
//  AppLocker
//
//  Created by Doe Phương on 20/11/26.
//

import Foundation

enum AppRelocationResult: Equatable, Sendable {
    case relocatedViaFileManager(destination: URL, trashErrorDescription: String?)
    case relocatedViaPrivilegedScript(destination: URL, fileManagerError: String)
    case failed(fileManagerError: String, scriptError: String?)
}

enum AppDirectoryPolicy {
    static let defaultAllowedDirectories = ["/Applications"]
    static let defaultTargetDirectory = URL(fileURLWithPath: "/Applications")

    static func isAllowedLocation(
        for bundleURL: URL,
        allowedDirectories: [String] = defaultAllowedDirectories
    ) -> Bool {
        let currentPath = bundleURL.standardizedFileURL.deletingLastPathComponent().path
        return allowedDirectories.contains { directory in
            let normalized = normalizeDirectoryPath(directory)
            if normalized == "/" {
                return currentPath.hasPrefix("/")
            }
            return currentPath == normalized || currentPath.hasPrefix(normalized + "/")
        }
    }

    static func abbreviatedDisplayPath(for bundleURL: URL, maxLength: Int = 50) -> String {
        let currentPath = bundleURL.standardizedFileURL.deletingLastPathComponent().path
        let abbreviated = (currentPath as NSString).abbreviatingWithTildeInPath
        let components = abbreviated.components(separatedBy: "/")
        guard abbreviated.count > maxLength, components.count > 4 else {
            return abbreviated
        }
        let firstPart = components.prefix(2).joined(separator: "/")
        let lastPart = components.suffix(2).joined(separator: "/")
        return "\(firstPart)/.../\(lastPart)"
    }

    static func destinationURL(
        for bundleURL: URL,
        in targetDirectory: URL = defaultTargetDirectory
    ) -> URL {
        targetDirectory.standardizedFileURL
            .appendingPathComponent(bundleURL.lastPathComponent, isDirectory: false)
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func privilegedShellCommand(
        from sourceURL: URL,
        to destinationURL: URL,
        stagingName: String? = nil
    ) -> String {
        let resolvedStagingName = stagingName ?? ".\(destinationURL.lastPathComponent).staging.\(UUID().uuidString)"
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(resolvedStagingName)

        let src = shellQuoted(sourceURL.path)
        let dest = shellQuoted(destinationURL.path)
        let stage = shellQuoted(stagingURL.path)

        return "(rm -rf \(stage) && cp -R \(src) \(stage) || { rm -rf \(stage); exit 1; })"
            + " && rm -rf \(dest) && mv \(stage) \(dest) && (rm -rf \(src) || true)"
    }

    static func privilegedInstallScript(
        from sourceURL: URL,
        to destinationURL: URL,
        stagingName: String? = nil
    ) -> String {
        let shellCommand = privilegedShellCommand(
            from: sourceURL,
            to: destinationURL,
            stagingName: stagingName
        )
        return "do shell script \(appleScriptStringLiteral(shellCommand)) with administrator privileges"
    }

    static func relocate(
        from sourceURL: URL,
        to targetDirectory: URL = defaultTargetDirectory,
        fileManager: FileManager = .default,
        trashSource: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        runPrivilegedScript: (String) -> String?
    ) -> AppRelocationResult {
        let destination = destinationURL(for: sourceURL, in: targetDirectory)
        do {
            try installAtomically(
                from: sourceURL,
                to: destination,
                fileManager: fileManager
            )
            let trashError = trashBundleNonFatal(at: sourceURL, trashSource: trashSource)
            return .relocatedViaFileManager(
                destination: destination,
                trashErrorDescription: trashError
            )
        } catch {
            let script = privilegedInstallScript(from: sourceURL, to: destination)
            if let scriptError = runPrivilegedScript(script) {
                return .failed(
                    fileManagerError: error.localizedDescription,
                    scriptError: scriptError
                )
            }
            return .relocatedViaPrivilegedScript(
                destination: destination,
                fileManagerError: error.localizedDescription
            )
        }
    }

    private static func installAtomically(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).staging.\(UUID().uuidString)")

        do {
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch {
            if fileManager.fileExists(atPath: stagingURL.path) {
                do {
                    try fileManager.removeItem(at: stagingURL)
                } catch {
                    // Best-effort staging cleanup; rethrow the original installation failure.
                }
            }
            throw error
        }
    }

    private static func trashBundleNonFatal(
        at sourceURL: URL,
        trashSource: (URL) throws -> Void
    ) -> String? {
        do {
            try trashSource(sourceURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func normalizeDirectoryPath(_ path: String) -> String {
        guard path.count > 1 else { return path }
        var normalized = path
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
