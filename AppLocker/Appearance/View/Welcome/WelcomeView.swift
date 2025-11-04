//
//  WelcomeView.swift
//  AppLocker
//
//  Created by Doe Phương on 27/9/25.
//

import SwiftUI

struct WelcomeView: View {
    @AppStorage("selectedMode") private var selectedMode: String? // Lưu user chọn
    @State private var shouldRestart = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 15) {
            if shouldRestart {
                Color.clear
                    .onAppear {
                        AppDelegate.shared.restartApp()
                    }
            } else {
                VStack(spacing: 10) {
                    Text("Welcome to AppLocker")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text("Please choose your preferred lock method:")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 40) {
                    LockModeButton(title: "Launcher", iconName: "lock.fill") {
                        selectedMode = "Launcher"
                        shouldRestart = true
                    }

                    LockModeButton(title: "ES (Endpoint Security)", iconName: "shield.fill") {
                        selectedMode = "ES"
                        shouldRestart = true
                    }
                }
                
                Spacer()
                
                Button(action: {
                    // Hủy màn hình welcome
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .padding()
                        .frame(width: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 2)
                        )
                }
            }
        }
        .padding(50)
        .frame(width: 550, height: 350)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(radius: 10)
        )
    }
}

// MARK: - Button Reusable
struct LockModeButton: View {
    let title: String
    let iconName: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(width: 150, height: 150)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    WelcomeView()
}
