//
//  WelcomeView.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import SwiftUI

struct WelcomeView: View {
    private var isMock: Bool
    let bundle = Bundle.main

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    private var licenseText: String {
        if let url = Bundle.main.url(forResource: "License", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return "License agreement details..."
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: bundle.appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(.top, 16)

            Text("Welcome to \(bundle.appName)")
                .font(.title2)
                .fontWeight(.bold)

            Text("Please read and agree to the terms of service and license below:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            ScrollView {
                Text(licenseText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            HStack(spacing: 16) {
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action: {
                    let response = AlertShow.show(
                        title: String(localized: "Confirm"),
                        message: String(localized: "Do you agree to the terms of service and license above?"),
                        style: .informational,
                        buttons: [
                            String(localized: "Agree"),
                            String(localized: "No")
                        ],
                        cancelIndex: 1,
                        defaultIndex: 0
                    )
                    
                    if case .button(index: 0, _) = response {
                        guard !isMock else { return }
                        UserDefaults.standard.set(false, forKey: "isFirstStart")
                        NSApp.appDelegate?.registerAgentWithoutImmediateLaunch()
                        WelcomeWindowController.shared?.isCompletingOnboarding = true
                        WelcomeWindowController.shared?.window?.close()
                        NSApp.appDelegate?.launchConfig()
                    }
                }) {
                    Text("Continue")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 10)
        }
        .safeAreaInset(edge: .bottom) {
            Text(bundle.copyright)
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.bottom, 16)
        }
        .frame(minWidth: WindowLayout.Welcome.size.width, minHeight: WindowLayout.Welcome.size.height)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    WelcomeView(isMock: true)
        .frame(width: WindowLayout.Welcome.size.width,
               height: WindowLayout.Welcome.size.height)
}
