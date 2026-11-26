import PhotosUI
import SwiftUI

@MainActor
struct PassListView: View {
    @EnvironmentObject private var store: PassStore
    @State private var pickerItem: PhotosPickerItem?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if store.passes.isEmpty {
                    EmptyPassesView()
                } else {
                    passList
                }
            }
            .navigationTitle("凭证")
            .toolbar { toolbar }
            .overlay {
                if store.isRecognizing {
                    RecognizingOverlay(message: store.progressMessage,
                                       startedAt: store.recognitionStartedAt ?? .now)
                }
            }
            .alert("识别失败", isPresented: errorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let item = newValue else { return }
            pickerItem = nil
            Task { await load(item) }
        }
        .alert("识别结果", isPresented: noteBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.lastResultNote ?? "")
        }
    }

    private var passList: some View {
        List {
            if !store.activePasses.isEmpty {
                Section("进行中") {
                    ForEach(store.activePasses) { pass in
                        PassRowView(pass: pass)
                    }
                }
            }
            if !store.completedPasses.isEmpty {
                Section("已完成") {
                    ForEach(store.completedPasses) { pass in
                        PassRowView(pass: pass)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// One plus button is the whole primary surface; everything else lives in
    /// the overflow menu.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("添加凭证", systemImage: "plus")
            }
            .disabled(store.isRecognizing)
        }
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                if LiveActivityController.runningCount > 0 {
                    Button(role: .destructive) {
                        LiveActivityController.endAll()
                        for pass in store.activePasses {
                            store.setPinned(false, for: pass)
                        }
                    } label: {
                        Label("取消全部锁屏卡片", systemImage: "lock.open")
                    }
                }
                if !store.completedPasses.isEmpty {
                    Button(role: .destructive) {
                        store.deleteAllCompleted()
                    } label: {
                        Label("清空已完成", systemImage: "trash")
                    }
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                store.lastError = "读不出这张图片的内容，换一张试试。"
                return
            }
            await store.recognize(imageData: data)
        } catch {
            store.lastError = "读取照片失败：\(error.localizedDescription)"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } })
    }

    private var noteBinding: Binding<Bool> {
        Binding(get: { store.lastResultNote != nil },
                set: { if !$0 { store.lastResultNote = nil } })
    }
}

struct EmptyPassesView: View {
    var body: some View {
        ContentUnavailableView {
            Label("还没有凭证", systemImage: "ticket")
        } description: {
            Text("点右上角的加号，选一张取餐码、车票、机票或电影票的截图。")
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

/// Recognition costs 10-20 s of paid model time. An elapsed counter is the only
/// honest progress signal available for a single opaque HTTP call.
struct RecognizingOverlay: View {
    let message: String
    let startedAt: Date

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(startedAt))
                    Text("已等待 \(seconds) 秒")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
