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

    private static let licenseContent: String = {
        if let url = Bundle.main.url(forResource: "License", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return "License agreement details..."
    }()

    private var licenseText: String {
        Self.licenseContent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(nsImage: bundle.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)

                Text("Welcome to \(bundle.appName)")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Please review the software license below:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)

                ScrollView {
                    Text(licenseText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.8)
                )
                .padding(.horizontal, 14)

                HStack(spacing: 12) {
                    Button(
                        action: {
                            NSApp.terminate(nil)
                        },
                        label: {
                            Text("Quit")
                                .font(.body)
                                .frame(maxWidth: .infinity)
                        }
                    )
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                    Button(
                        action: {
                            let response = AlertShow.show(
                                title: String(localized: "Confirm"),
                                message: String(
                                    localized: "Do you acknowledge the software license and disclaimer above?"
                                ),
                                style: .informational,
                                buttons: [
                                    String(localized: "Agree"),
                                    String(localized: "Decline")
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
                        },
                        label: {
                            Text("Continue")
                                .font(.body)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    )
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .navigationTitle("Welcome to \(bundle.appName)")
            .toolbar {
                // Empty toolbar for Liquid Glass bridging without bordered pill item
            }
            .safeAreaInset(edge: .bottom) {
                Text(bundle.copyright)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: WindowLayout.welcomeSize.width, height: WindowLayout.welcomeSize.height)
    }
}

#Preview {
    WelcomeView(isMock: true)
        .frame(width: WindowLayout.welcomeSize.width,
               height: WindowLayout.welcomeSize.height)
}
