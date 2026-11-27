//
//  AddAppSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct AddAppSheet: View {
    @Bindable var appState: AppState
    @FocusState var isSearchFocused: Bool
    let unfocus: () -> Void
    @State private var maxButtonWidth: CGFloat?

    private var lockButtonTitle: String {
        let count = appState.selectedToLock.count
        if count == 0 {
            return String(localized: "Lock")
        } else {
            return String(format: String(localized: "Lock (%d)"), count)
        }
    }

    private var isSearching: Bool {
        !appState.searchTextUnlockableApps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            topSearchHeader

            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomActionBar
        }
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture { unfocus() }
        .frame(
            minWidth: WindowLayout.addAppMinSize.width,
            minHeight: WindowLayout.addAppMinSize.height
        )
        .onDisappear {
            appState.searchTextUnlockableApps = ""
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if isSearching && appState.filteredUnlockableApps.isEmpty {
            ContentUnavailableView.search(text: appState.searchTextUnlockableApps)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            appScrollView
        }
    }

    @ViewBuilder
    private var appScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                let userApps = appState.userUnlockableApps
                if !userApps.isEmpty {
                    SectionHeader("Applications")
                    ForEach(userApps, id: \.path) { app in
                        AddAppRow(
                            for: app,
                            isSelected: appState.selectedToLock.contains(app.path),
                            onToggle: { toggleSelection(for: app.path) },
                            onUnfocus: unfocus
                        )
                    }
                }

                let systemApps = appState.systemUnlockableApps
                if !systemApps.isEmpty {
                    SectionHeader("System Applications")
                        .padding(.top, 10)
                    ForEach(systemApps, id: \.path) { app in
                        AddAppRow(
                            for: app,
                            isSelected: appState.selectedToLock.contains(app.path),
                            onToggle: { toggleSelection(for: app.path) },
                            onUnfocus: unfocus
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .clipped()
    }

    @ViewBuilder
    private var topSearchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select the application to lock")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                TextField(
                    "Search apps...", text: $appState.searchTextUnlockableApps
                )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { unfocus() }
                .onExitCommand { unfocus() }

                if !appState.searchTextUnlockableApps.isEmpty {
                    Button {
                        appState.searchTextUnlockableApps = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Clear search"))
                    .accessibilityLabel(String(localized: "Clear search"))
                }
            }
            .padding(7)
            .contentShape(Capsule())
            .onTapGesture { isSearchFocused = true }
            .liquidGlassCapsule()
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button(
                action: {
                    appState.addOtherApps(over: NSApp.keyWindow)
                },
                label: {
                    Text(String(localized: "Others…"))
                        .equalWidthButtonLabel(minWidth: maxButtonWidth)
                }
            )
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            HStack(spacing: 10) {
                Button(
                    action: {
                        appState.dismissAddAppSheet()
                    },
                    label: {
                        Text(String(localized: "Close"))
                            .equalWidthButtonLabel(minWidth: maxButtonWidth)
                    }
                )
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button(
                    action: {
                        appState.lockSelectedApps()
                    },
                    label: {
                        Text(lockButtonTitle)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(appState.selectedToLock.count)))
                            .equalWidthButtonLabel(minWidth: maxButtonWidth)
                    }
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(appState.selectedToLock.isEmpty)
                .animation(.snappy(duration: 0.25), value: appState.selectedToLock.count)
            }
        }
        .syncEqualWidth(into: $maxButtonWidth)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private func toggleSelection(for path: String) {
        if appState.selectedToLock.contains(path) {
            appState.selectedToLock.remove(path)
        } else {
            appState.selectedToLock.insert(path)
        }
    }
}

#if DEBUG
#Preview {
    AddAppSheet(
        appState: .preview(locked: []),
        unfocus: {}
    )
}

#Preview("No Search Results") {
    let state = AppState.preview(locked: [])
    state.searchTextUnlockableApps = "NonExistentApp"
    state.filteredUnlockableApps = []
    return AddAppSheet(
        appState: state,
        unfocus: {}
    )
}
#endif
