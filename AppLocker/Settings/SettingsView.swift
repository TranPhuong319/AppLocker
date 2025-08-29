import SwiftUI
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable = "Stable"   // giá trị cố định cho code / lưu UserDefaults
    case beta = "Beta"

    var id: String { self.rawValue }

    // Hiển thị tên cho UI, có thể localize
    var displayName: String {
        switch self {
        case .stable: return "Stable".localized
        case .beta: return "Beta".localized
        }
    }
}

struct SettingsView: View {
    @State private var autoCheck = false
    @State private var autoDownload = false
    
    // Lấy giá trị từ UserDefaults hoặc mặc định là Stable
    @State private var selectedChannel: UpdateChannel = {
        let saved = UserDefaults.standard.string(forKey: "updateChannel") ?? UpdateChannel.stable.rawValue
        return UpdateChannel(rawValue: saved) ?? .stable
    }()

    var body: some View {
        Form {
            Section() {
                Toggle("Automatically check for updates.".localized, isOn: $autoCheck)
                    .onChange(of: autoCheck) { newValue in
                        AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
                    }

                Toggle("Automatically download new updates.".localized, isOn: $autoDownload)
                    .onChange(of: autoDownload) { newValue in
                        AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates = newValue
                    }
                
                Picker("Update Channel".localized, selection: $selectedChannel) {
                    ForEach(UpdateChannel.allCases, id: \.self) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .onChange(of: selectedChannel) { newChannel in
                    UserDefaults.standard.set(newChannel.rawValue, forKey: "updateChannel")
                    
                    DispatchQueue.main.async {
                        switch newChannel {
                        case .stable:
                            AppUpdater.shared.checkForUpdates(useBeta: false)
                        case .beta:
                            AppUpdater.shared.checkForUpdates(useBeta: true)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            let updater = AppUpdater.shared.updaterController.updater
            autoCheck = updater.automaticallyChecksForUpdates
            autoDownload = updater.automaticallyDownloadsUpdates
        }
    }
}

#Preview{
    SettingsView()
}
