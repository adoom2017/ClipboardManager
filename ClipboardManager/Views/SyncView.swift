import SwiftUI

struct SyncView: View {
    @ObservedObject var viewModel: SyncViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("局域网同步", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Text("设备会在局域网内自动发现。两端配置相同的 6 位 PIN 后，文本会通过 AES-GCM 加密传输。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack {
                    Text("同步 PIN")
                    SecureField("6 位数字", text: $settingsViewModel.syncPIN)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Spacer()
                    Label(
                        settingsViewModel.syncPIN.count == 6 ? "已配置" : "未配置",
                        systemImage: settingsViewModel.syncPIN.count == 6 ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(settingsViewModel.syncPIN.count == 6 ? .green : .secondary)
                }
            }
            .padding(15)
            .panelSectionSurface(cornerRadius: 15, fillOpacity: 0.30)

            HStack {
                Label("已发现服务", systemImage: "bonjour")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.discoveredPeers.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                .panelSectionSurface(cornerRadius: 15, fillOpacity: 0.26)
            }
        }
        .padding(20)
        .onAppear {
            viewModel.boostDiscovery()
        }
    }
}
