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
                            MissingAppRow(for: app)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .clipped()

                bottomActionBar
            }
        }
        .frame(
            minWidth: WindowLayout.missingAppsMinSize.width,
            minHeight: WindowLayout.missingAppsMinSize.height
        )
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
                        .equalWidthButtonLabel(minWidth: maxButtonWidth, horizontalPadding: 8)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button(
                action: {
                    appState.hideMissingApps(for: missingPaths)
                },
                label: {
                    Text(String(localized: "Hide"))
                        .font(.system(size: 13, weight: .medium))
                        .equalWidthButtonLabel(minWidth: maxButtonWidth, horizontalPadding: 8)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(
                action: {
                    appState.deleteMissingApps(for: missingPaths)
                },
                label: {
                    Text(String(localized: "Remove"))
                        .font(.system(size: 13, weight: .semibold))
                        .equalWidthButtonLabel(minWidth: maxButtonWidth, horizontalPadding: 8)
                }
            )
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .syncEqualWidth(into: $maxButtonWidth)
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}
