import SwiftUI

struct SyncView: View {
    @ObservedObject var viewModel: SyncViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设备会在局域网内自动发现。点击剪贴板条目的同步按钮时，应用会临时连接目标设备并发送该条文本内容。")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
