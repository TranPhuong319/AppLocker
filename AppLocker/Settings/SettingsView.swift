//
//  SettingsView.swift
//  AppLocker
//
//  Copyright © 2025 TranPhuong319. All rights reserved.
//


import SwiftUI

extension View {
    func applyAccent() -> some View {
        self.accentColor(.accentColor)
    }
}

struct SettingsView: View {
    enum Tab {
        case general, update, security
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Cài đặt chung", systemImage: "gear")
                    .tag(Tab.general)
                Label("Cập nhật", systemImage: "arrow.triangle.2.circlepath")
                    .tag(Tab.update)
                Label("Bảo mật", systemImage: "lock.shield")
                    .tag(Tab.security)
            }
            .applyAccent() // áp accent cho menu
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .update:
                UpdateSettingsView()
            case .security:
                SecuritySettingsView()
            }
        }
        .applyAccent() // áp accent cho detail view luôn
    }
}

struct SecuritySettingsView: View {
    @State private var requirePassword = true
    @State private var lockAfterSeconds = 60

    var body: some View {
        Form {
            Toggle("Yêu cầu mật khẩu khi mở app", isOn: $requirePassword)
                .applyAccent()
                .onChange(of: requirePassword) { newValue in
                    print("Require password:", newValue)
                }
                .applyAccent()
                .toggleStyle(.switch)

            Stepper(value: $lockAfterSeconds, in: 10...600, step: 10) {
                Text("Tự động khoá sau \(lockAfterSeconds) giây")
            }
            .applyAccent()
            .onChange(of: lockAfterSeconds) { newValue in
                print("Lock after:", newValue)
            }
        }
        .padding()
    }
}

struct UpdateSettingsView: View {
    @State private var autoUpdate = true
    @State private var lastChecked = Date()

    var body: some View {
        Form {
            Toggle("Tự động kiểm tra cập nhật", isOn: $autoUpdate)
                .applyAccent()
                .onChange(of: autoUpdate) { newValue in
                    print("Auto update:", newValue)
                }
                .applyAccent()
                .toggleStyle(.switch)

            HStack {
                Text("Lần kiểm tra cuối:")
                Spacer()
                Text(lastChecked, style: .date)
            }

            Button("Kiểm tra ngay") {
                lastChecked = Date()
                print("Đang kiểm tra cập nhật...")
            }
            .applyAccent()
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("theme") private var theme = "Hệ thống"

    var body: some View {
        Form {
            Toggle("Khởi động cùng macOS", isOn: $launchAtLogin)
                .applyAccent()
                .onChange(of: launchAtLogin) { newValue in
                    print("Launch at login:", newValue)
                }
                .applyAccent()
                .toggleStyle(.switch)

            Picker("Giao diện", selection: $theme) {
                Text("Hệ thống").tag("Hệ thống")
                Text("Sáng").tag("Sáng")
                Text("Tối").tag("Tối")
            }
            .applyAccent()
            .pickerStyle(.segmented)    // thử kiểu thanh phân đoạn
            .onChange(of: theme) { newValue in
                print("Theme:", newValue)
            }
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}

