import SwiftUI
import Sparkle

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable = "Stable"   // giá trị cố định cho code / lưu UserDefaults
    case beta = "Beta"

    var id: String { self.rawValue }

    // Hiển thị tên cho UI, có thể localize
    var displayName: LocalizedStringKey {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        }
    }
    var description: LocalizedStringKey {
        switch self {
        case .stable:
            return "Get official, stable updates."
        case .beta:
            return """
            Get experimental updates.
            Note: Experimental updates are often unstable.
            """
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
                Section {
                    Group {
                        Toggle("Automatically check for updates.", isOn: $autoCheck)
                            .onChange(of: autoCheck) { newValue in
                                AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
                            }

                        Toggle("Automatically download new updates.", isOn: $autoDownload)
                            .onChange(of: autoDownload) { newValue in
                                AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates = newValue
                            }
                    }
                    Picker("Update Channel", selection: $selectedChannel) {
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
        }
        .fixedSize()
        .padding()
        .onAppear {
            let updater = AppUpdater.shared.updaterController.updater
            autoCheck = updater.automaticallyChecksForUpdates
            autoDownload = updater.automaticallyDownloadsUpdates
        }
    }
}

#Preview {
    SettingsView()
}
