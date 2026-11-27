import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverText = AppSettings.shared.serverURLString
    @State private var tokenText = AppSettings.shared.serverToken
    @State private var testState: TestState = .idle

    private enum TestState {
        case idle
        case testing
        case ok(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.20:8787", text: $serverText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: serverText) { _, newValue in
                            AppSettings.shared.serverURLString = newValue
                            if case .ok = testState { testState = .idle }
                        }

                    SecureField("访问令牌（后端没设就留空）", text: $tokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: tokenText) { _, newValue in
                            AppSettings.shared.serverToken = newValue
                            if case .ok = testState { testState = .idle }
                        }

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            switch testState {
                            case .idle: EmptyView()
                            case .testing: ProgressView()
                            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(isTesting)
                } header: {
                    Text("后端地址")
                } footer: {
                    statusFooter
                }

                Section("锁屏卡片") {
                    LabeledContent("实时活动") {
                        if LiveActivityController.isSupported {
                            Text("已开启").foregroundStyle(.green)
                        } else {
                            Text("未开启").foregroundStyle(.red)
                        }
                    }
                    if !LiveActivityController.isSupported {
                        Text("到「设置 → 喵卡 → 实时活动」打开，否则固定到锁屏不会生效。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("截图去哪了") {
                    Text("你选的截图会发送到上面填的这个后端，由后端调用多模态模型识别，App 本身不保存模型密钥，也不直接连模型厂商。")
                    Text("识别结果只存在这台手机的 App 目录里。删除凭证不会删除原始截图。")
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    Text("目前支持：取餐码、快递取件码、火车票、机票、电影票、演出票、打车订单、兑换券、订阅账单。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch testState {
        case .idle:
            Text("填后端的地址：自己电脑上跑就填局域网 IP，云上部署就填 https 公网地址；令牌要和后端的 PASSCARD_TOKEN 一致，后端没设就留空。")
        case .testing:
            Text("正在连接…")
        case .ok(let model):
            Text("连上了。模型：\(model)")
        case .failed(let message):
            Text(message)
        }
    }

    private func testConnection() {
        AppSettings.shared.serverURLString = serverText
        guard let url = AppSettings.shared.serverURL else {
            testState = .failed("地址格式不对，应该像 http://192.168.1.20:8787")
            return
        }
        testState = .testing
        Task {
            do {
                let model = try await RecognitionClient(baseURL: url, timeout: 15,
                                                        token: AppSettings.shared.serverToken).checkHealth()
                testState = .ok(model)
            } catch {
                testState = .failed(error.localizedDescription)
            }
        }
    }
}
