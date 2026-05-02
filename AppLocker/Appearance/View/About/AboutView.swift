//
//  AboutView.swift
//  AppLocker
//
//  Created by AppLocker
//

import SwiftUI

struct AboutView: View {
    let bundle = Bundle.main
    @Environment(\.openURL) var openURL
    @State private var isProtectionEnabled: Bool = !AppState.shared.manager.isProtectionDisabled
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Image(nsImage: bundle.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                
                Text(bundle.appName)
                    .font(.system(size: 32, weight: .bold))
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            // Info Card
            GroupBox {
                VStack(spacing: 12) {
                    HStack {
                        Text("Application lock")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { isProtectionEnabled },
                            set: { newValue in
                                handleToggle(newValue: newValue)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    
                    HStack {
                        Text(isProtectionEnabled ? "The application is locked"
                             : "The application is not locked")
                            .font(.subheadline)
                            .foregroundColor(isProtectionEnabled ? .green : .red)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 40)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in
                isProtectionEnabled = !AppState.shared.manager.isProtectionDisabled
            }
            
            Spacer()
            
            // Footer Area
            VStack(spacing: 12) {
                Text(bundle.detailedVersion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(bundle.copyright)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Link("Website", destination: URL(string: "https://github.com/TranPhuong319/AppLocker")!)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 450, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func handleToggle(newValue: Bool) {
        if newValue == false {
            AuthenticationManager.authenticate(
                reason: String(localized: "disable application lock")
            ) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        AppState.shared.manager.setProtectionDisabled(true)
                        self.isProtectionEnabled = false
                    } else {
                        // Revert back if failed
                        self.isProtectionEnabled = true
                    }
                }
            }
        } else {
            AppState.shared.manager.setProtectionDisabled(false)
            self.isProtectionEnabled = true
        }
    }
}

#Preview {
    AboutView()
}
