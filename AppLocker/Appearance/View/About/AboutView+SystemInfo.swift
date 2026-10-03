//
//  AboutView+SystemInfo.swift
//  AppLocker
//
//  Created by Doe Phương on 03/10/26.
//

import SwiftUI
import Darwin

// MARK: - System Environment Inspector

enum SystemEnvironment {
    static var cpuBrand: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown CPU" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = buffer.withUnsafeBufferPointer { ptr -> String in
            guard let baseAddress = ptr.baseAddress else { return "" }
            return String(cString: baseAddress)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? "Apple Silicon" : brand
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let patchSuffix = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        let versionStr = "\(version.majorVersion).\(version.minorVersion)\(patchSuffix)"

        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
            let build = buffer.withUnsafeBufferPointer { ptr -> String in
                guard let baseAddress = ptr.baseAddress else { return "" }
                return String(cString: baseAddress)
            }.trimmingCharacters(in: .whitespacesAndNewlines)
            return "macOS \(versionStr) (\(build))"
        }
        return "macOS \(versionStr)"
    }

    static var isRunningUnderRosetta: Bool {
        var isTranslated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &isTranslated, &size, nil, 0) == 0 {
            return isTranslated == 1
        }
        return false
    }

    static var architectureDetail: String {
        #if arch(arm64)
        return "ARM64 (Apple Silicon)"
        #elseif arch(x86_64)
        return isRunningUnderRosetta ? "x86_64 (Rosetta 2)" : "x86_64 (Native Intel)"
        #else
        return "Universal"
        #endif
    }
}

// MARK: - AboutView System Info Popover

extension AboutView {
    @ViewBuilder
    var systemInfoPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("System Information")
                    .font(.system(size: 11, weight: .semibold))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                systemInfoRow(label: "Processor", value: SystemEnvironment.cpuBrand)
                systemInfoRow(label: "Architecture", value: SystemEnvironment.architectureDetail)
                systemInfoRow(label: "Operating System", value: SystemEnvironment.osVersion)
            }
        }
        .padding(10)
        .frame(width: 250)
    }

    private func systemInfoRow(label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
