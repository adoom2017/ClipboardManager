import SwiftUI

struct SyncView: View {
    @ObservedObject var viewModel: SyncViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 自动同步开关
            Toggle("自动同步", isOn: $viewModel.isAutoSyncEnabled)
            Text("开启后，新增的文本条目将自动推送给所有已连接设备。")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            // 已配对设备
            HStack {
                Text("已配对设备")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.startDiscovery() }) {
                    Label("添加设备", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            if viewModel.pairedPeers.isEmpty {
                Text("暂无已配对设备。点击「添加设备」发现局域网内的其他 ClipboardManager。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(viewModel.pairedPeers) { peer in
                    HStack {
                        Image(systemName: viewModel.isOnline(peer.id) ? "wifi" : "wifi.slash")
                            .foregroundColor(viewModel.isOnline(peer.id) ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(.body)
                            Text(viewModel.isOnline(peer.id) ? "已连接" : "离线")
                                .font(.caption)
                                .foregroundColor(viewModel.isOnline(peer.id) ? .green : .secondary)
                        }
                        Spacer()
                        Button(action: { viewModel.removePeer(id: peer.id) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("解除配对")
                    }
                    .padding(.vertical, 4)
                }
            }

            // 等待对端输入 PIN（本机显示的 PIN）
            if let pin = viewModel.incomingPIN {
                Divider()
                VStack(spacing: 8) {
                    Text("对端正在请求配对，请让对方在其设备上输入以下 PIN：")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pin)
                        .font(.system(.largeTitle, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Text("PIN 仅用于本次配对，完成后自动失效。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(20)
        // 发现周边设备 sheet
        .sheet(isPresented: $viewModel.showDiscoveredPeers) {
            DiscoveredPeersSheet(viewModel: viewModel)
        }
        // PIN 输入 sheet（发起方）
        .sheet(isPresented: $viewModel.showPinInput) {
            PinInputSheet(viewModel: viewModel)
        }
    }
}

// MARK: - 发现设备 Sheet

struct DiscoveredPeersSheet: View {
    @ObservedObject var viewModel: SyncViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("发现的设备")
                    .font(.headline)
                Spacer()
                Button("关闭") { viewModel.stopDiscovery(); dismiss() }
            }
            .padding()

            Divider()

            if viewModel.discoveredPeers.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在局域网内搜索其他 ClipboardManager…")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(viewModel.discoveredPeers) { peer in
                    HStack {
                        Image(systemName: "macbook")
                        Text(peer.name)
                        Spacer()
                        Button("配对") {
                            viewModel.connectToPeer(peer)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .frame(width: 320, height: 300)
    }
}

// MARK: - PIN 输入 Sheet（发起方）

struct PinInputSheet: View {
    @ObservedObject var viewModel: SyncViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("输入配对 PIN")
                .font(.headline)
            Text("请输入对方设备上显示的 6 位 PIN 码：")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            TextField("000000", text: $viewModel.pinInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 140)
            HStack(spacing: 12) {
                Button("取消") {
                    viewModel.pinInput = ""
                    dismiss()
                }
                Button("确认配对") {
                    viewModel.confirmPin()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.pinInput.count != 6)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}
