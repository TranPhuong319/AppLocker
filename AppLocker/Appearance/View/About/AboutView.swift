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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Image(nsImage: bundle.appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)

                Text(bundle.appName)
                    .font(.system(size: 32, weight: .bold))
            }
            .padding(.top, 28)
            .padding(.bottom, 10)

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
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    AboutView()
}
