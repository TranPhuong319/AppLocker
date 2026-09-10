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
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 6) {
                    Image(nsImage: bundle.appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)

                    Text(bundle.appName)
                        .font(.system(size: 32, weight: .bold))

                    Text("Version \(bundle.fullVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
            .navigationTitle("")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(bundle.copyright)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Link("Website", destination: URL(string: "https://github.com/TranPhuong319/AppLocker")!)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .frame(width: WindowLayout.aboutSize.width, height: WindowLayout.aboutSize.height)
    }
}

#Preview {
    AboutView()
        .frame(width: WindowLayout.aboutSize.width,
               height: WindowLayout.aboutSize.height)
}
