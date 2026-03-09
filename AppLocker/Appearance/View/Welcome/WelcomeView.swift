//
//  WelcomeView.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import SwiftUI

struct WelcomeView: View {
    @AppStorage("selectedMode") private var selectedMode: String = ""
    @State private var shouldRestart = false
    private var isMock: Bool

    init(isMock: Bool = false) {
        self.isMock = isMock
    }

    var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "No information available"
    }

    var body: some View {
        VStack(spacing: 20) {
            if shouldRestart {
                Color.clear
                    .onAppear {
                        NSApp.appDelegate?.restartApp(mode: AppMode(rawValue: selectedMode))
                    }
            } else {
                Spacer(minLength: 20)

                if let icon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                }

                Text("Welcome to AppLocker")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Please choose your preferred lock method:")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                VStack(spacing: 20) {
                    let isESEnabled = isMock ? true : isKextSigningDisabled()

                    LabelButtonView(label: "ES (EndpointSecurity)",
                                    symbol: "lock.shield.fill",
                                    isDisabled: !isESEnabled) {
                        guard !isMock else { return }
                        selectedMode = AppMode.esMode.rawValue
                        shouldRestart = true
                    }
                    .disabled(!isESEnabled)
                    .help(isESEnabled ? "" : "SIP must be disabled to use this mode")

                    LabelButtonView(label: "Launcher",
                                    symbol: "lock.rectangle.fill") {
                        guard !isMock else { return }
                        selectedMode = AppMode.launcher.rawValue
                        shouldRestart = true
                    }
                }
                .padding(.horizontal, 20)

                Spacer() // đẩy nội dung lên trên
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(copyright)
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.bottom, 16)
        }
        .frame(minWidth: WindowLayout.Welcome.size.width, minHeight: WindowLayout.Welcome.size.height)
        .background(Color(NSColor.windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }
}

#Preview {
    WelcomeView(isMock: true)
        .frame(width: WindowLayout.Welcome.size.width,
               height: WindowLayout.Welcome.size.height)
}
