import SwiftUI

struct SyncView: View {
    @ObservedObject var viewModel: SyncViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设备会在局域网内自动发现。两端配置相同的 6 位 PIN 后，文本会通过 AES-GCM 加密传输。")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("同步 PIN")
                SecureField("6 位数字", text: $settingsViewModel.syncPIN)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
                Text(settingsViewModel.syncPIN.count == 6 ? "已配置" : "未配置")
                    .font(.caption)
                    .foregroundStyle(settingsViewModel.syncPIN.count == 6 ? .green : .secondary)
            }

            Divider()

            HStack {
                Text("已发现服务")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.discoveredPeers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.discoveredPeers.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在搜索局域网内的 ClipboardManager 服务…")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.discoveredPeers) { peer in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(peer.displayName)
                            .font(.body)
                        if let host = peer.host, let port = peer.port {
                            Text("\(host):\(port)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Bonjour 服务")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .onAppear {
            viewModel.boostDiscovery()
        }
    }
}
