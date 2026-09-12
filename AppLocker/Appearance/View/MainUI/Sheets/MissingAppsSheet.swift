//
//  MissingAppsSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct MissingAppsSheet: View {
    var appState: AppState
    @State private var maxButtonWidth: CGFloat?

    private var missingPaths: [String] {
        appState.confirmedMissingApps.map(\.path)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.confirmedMissingApps, id: \.path) { app in
                            MissingAppRow(app: app)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .clipped()

                bottomActionBar
            }
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            )
        }
        .frame(
            minWidth: WindowLayout.missingAppsMinSize.width,
            minHeight: WindowLayout.missingAppsMinSize.height
        )
        .task {
            appState.activeTouchBar = .missingAppsPopup
        }
        .onDisappear {
            appState.activeTouchBar = .mainWindow
        }
    }

    @ViewBuilder
    private var topHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text(String(localized: "Missing Applications"))
                    .font(.headline)
                Spacer()
            }

            Text(String(localized: "These applications no longer exist on disk but remain in your lock list."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Button(
                action: {
                    appState.closeMissingApps()
                },
                label: {
                    Text(String(localized: "Cancel"))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                            }
                        )
                        .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button(
                action: {
                    appState.hideMissingApps(paths: missingPaths)
                },
                label: {
                    Text(String(localized: "Hide"))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                            }
                        )
                        .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(
                action: {
                    appState.deleteMissingApps(paths: missingPaths)
                },
                label: {
                    Text(String(localized: "Remove"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: EqualWidthKey.self, value: geo.size.width)
                            }
                        )
                        .frame(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .onPreferenceChange(EqualWidthKey.self) { width in
            if width > 0 {
                self.maxButtonWidth = max(self.maxButtonWidth ?? 0, width)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}
