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
    var description: String {
        switch self {
        case .stable: return "Get official, stable updates.".localized
        case .beta: return "Get experimental updates.%@Note: Experimental updates are often unstable.".localized(with: "\n")
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
        VStack(alignment: .leading, spacing: 0) {
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.displayName)
                                    .font(.body)
                            }
                            .tag(channel)
                        }
                    }
                    .onChange(of: selectedChannel) { newChannel in
                        UserDefaults.standard.set(newChannel.rawValue, forKey: "updateChannel")
                        //
                        //                    DispatchQueue.main.async {
                        //                        switch newChannel {
                        //                        case .stable:
                        //                            AppUpdater.shared.checkForUpdates(useBeta: false)
                        //                        case .beta:
                        //                            AppUpdater.shared.checkForUpdates(useBeta: true)
                        //                        }
                        //                    }
                    }
                    
                    // Text mô tả, tự động thay đổi theo selectedChannel
                    Text(selectedChannel.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .frame(width: 390, height: 110, alignment: .top) // giữ kích thước gốc, căn top
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
