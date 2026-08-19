//
//  AddAppSheet.swift
//  AppLocker
//
//  Created by Doe Phương on 28/12/25.
//

import SwiftUI

struct AddAppSheet: View {
    @ObservedObject var appState: AppState
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

    var body: some View {
        VStack(spacing: 8) {
            topSearchHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    let userApps = appState.userUnlockableApps
                    if !userApps.isEmpty {
                        SectionHeader(title: "Applications")
                        ForEach(userApps, id: \.path) { app in
                            AddAppButton(
                                app: app,
                                isSelected: appState.selectedToLock.contains(app.path),
                                onToggle: { toggleSelection(for: app.path) },
                                unfocus: unfocus
                            )
                        }
                    }

                    let systemApps = appState.systemUnlockableApps
                    if !systemApps.isEmpty {
                        SectionHeader(title: "System Applications")
                            .padding(.top, 10)
                        ForEach(systemApps, id: \.path) { app in
                            AddAppButton(
                                app: app,
                                isSelected: appState.selectedToLock.contains(app.path),
                                onToggle: { toggleSelection(for: app.path) },
                                unfocus: unfocus
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .clipped()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: WindowLayout.addAppListMaxHeight)

            bottomActionBar
        }
        .padding(.top, 8)
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .contentShape(Rectangle())
        .onTapGesture { unfocus() }
        .frame(
            minWidth: WindowLayout.addAppMinSize.width,
            minHeight: WindowLayout.addAppMinSize.height
        )
        .onAppear {
            unfocus()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
                appState.activeTouchBar = .addAppPopup
            }
        }
        .onDisappear {
            // Thêm độ trễ nhỏ để đảm bảo window chính đã trở thành key trước khi apply lại Touch Bar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.searchTextUnlockaleApps = ""
                appState.activeTouchBar = .mainWindow
            }
        }
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
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField(
                    "Search apps...", text: $appState.searchTextUnlockaleApps
                )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { unfocus() }
                .onExitCommand { unfocus() }
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
                    appState.addOthersApp(over: NSApp.keyWindow)
                },
                label: {
                    Text(String(localized: "Others…"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
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

            HStack(spacing: 10) {
                Button(
                    action: {
                        appState.closeAddPopup()
                    },
                    label: {
                        Text(String(localized: "Close"))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
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
                .keyboardShortcut(.escape, modifiers: [])

                Button(
                    action: {
                        appState.lockButton()
                    },
                    label: {
                        Text(lockButtonTitle)
                            .monospacedDigit()
                            .numericTextTransition(value: Double(appState.selectedToLock.count))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
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
                .disabled(appState.selectedToLock.isEmpty || appState.isLocking)
                .animation(.snappy(duration: 0.25), value: appState.selectedToLock.count)
            }
        }
        .onPreferenceChange(EqualWidthKey.self) { width in
            if width > 0 {
                self.maxButtonWidth = max(self.maxButtonWidth ?? 0, width)
            }
        }
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

#Preview {
    AddAppSheet(
        appState: .preview(locked: []),
        unfocus: {}
    )
}
