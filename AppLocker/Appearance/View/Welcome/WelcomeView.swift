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
    @Environment(\.presentationMode) var presentationMode
    var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "Không có thông tin"
    }

    var body: some View {
        VStack(spacing: 20) {
            if shouldRestart {
                Color.clear
                    .onAppear {
                        AppDelegate.shared.restartApp(mode: selectedMode)
                    }
            } else {
                Spacer().frame(height: 20)
                
                // Icon lớn trên đầu
                if let icon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100) // chỉnh size icon cho vừa
                } else {
                    Text("No Icon")
                }
                
                // Title
                Text("Welcome to AppLocker")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Description
                Text("Please choose your preferred lock method:")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                // Hai label có icon nhỏ
                VStack(spacing: 20) {
                    LabelButtonView(label: "ES (EndpointSecurity)",
                                    symbol: "lock.shield.fill") {
                        selectedMode = "ES"
                        shouldRestart = true
                    }
                    
                    LabelButtonView(label: "Launcher",
                                    symbol: "lock.rectangle.fill") {
                        selectedMode = "Launcher"
                        shouldRestart = true
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer().frame(height: 1)
                
                // Footer text
                Text(copyright)
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.bottom, 30)
            }
        }
        .frame(width: 350, height: 450)
        .background(Color(NSColor
            .windowBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

// Component cho 1 label có icon nhỏ + text
struct LabelButtonView: View {
    let label: String
    let symbol: String
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 24))
                Text(label)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .brightness(isHovering ? 0.1 : 0)  // Tăng độ sáng 10% khi hover
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    WelcomeView()
}
