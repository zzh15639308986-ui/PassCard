import Foundation

/// Single JSON file in Application Support. No App Group, no Core Data: the
/// widget extension gets everything it needs from the activity payload.
@MainActor
final class PassStore: ObservableObject {
    @Published private(set) var passes: [Pass] = []
    @Published private(set) var isRecognizing = false
    @Published private(set) var recognitionStartedAt: Date?
    /// Shown verbatim under the spinner. Recognition takes 10-20 s, and a
    /// silent spinner reads as a hung app.
    @Published var progressMessage = ""
    @Published var lastError: String?
    /// Set after a recognition whose result failed backend validation, so the
    /// UI can say what is missing instead of failing silently.
    @Published var lastResultNote: String?

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = directory.appendingPathComponent("PassCards", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        self.fileURL = storeURL.appendingPathComponent("passes.json")
        load()
    }

    var activePasses: [Pass] { passes.filter { !$0.isCompleted } }
    var completedPasses: [Pass] { passes.filter(\.isCompleted) }

    // MARK: - Recognition

    func recognize(imageData: Data) async {
        guard !isRecognizing else { return }

        let client: RecognitionClient
        do {
            client = try RecognitionClient.current()
        } catch {
            lastError = error.localizedDescription
            return
        }

        isRecognizing = true
        recognitionStartedAt = Date()
        lastError = nil
        lastResultNote = nil
        progressMessage = "正在压缩图片…"

        let prepared = await Task.detached(priority: .userInitiated) {
            ImagePreparer.prepare(imageData)
        }.value

        progressMessage = "正在识别，通常需要 10 到 20 秒…"
        defer {
            isRecognizing = false
            recognitionStartedAt = nil
            progressMessage = ""
        }

        do {
            let result = try await client.recognize(prepared)
            let pass = Pass(type: result.type,
                            fields: result.fields,
                            imageSHA256: result.imageSha256)
            insert(pass)

            if result.ok {
                lastResultNote = nil
            } else if result.type == .unknown {
                lastResultNote = "这张截图里没有认出可用的凭证。已按「未识别」保存，你可以手动删掉。"
            } else {
                lastResultNote = "识别不完整：\(result.errors.joined(separator: "；"))"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mutations

    func insert(_ pass: Pass) {
        passes.insert(pass, at: 0)
        save()
    }

    func markCompleted(_ pass: Pass) {
        guard let index = passes.firstIndex(where: { $0.id == pass.id }) else { return }
        passes[index].markCompleted()
        save()
    }

    func reopen(_ pass: Pass) {
        guard let index = passes.firstIndex(where: { $0.id == pass.id }) else { return }
        passes[index].reopen()
        save()
    }

    func setPinned(_ pinned: Bool, for pass: Pass) {
        guard let index = passes.firstIndex(where: { $0.id == pass.id }) else { return }
        passes[index].isPinned = pinned
        save()
    }

    func delete(ids: [UUID]) {
        let removing = Set(ids)
        passes.removeAll { removing.contains($0.id) }
        save()
    }

    func deleteAllCompleted() {
        passes.removeAll(where: \.isCompleted)
        save()
    }

    // MARK: - Persistence

    /// Encoder and decoder must agree on the date strategy. A mismatch makes the
    /// stored file undecodable on the next launch, and load() reads that as
    /// corruption and throws the user's passes away.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            passes = try Self.makeDecoder().decode([Pass].self, from: data)
        } catch {
            // A corrupt store must not brick the app; keep the file for autopsy
            // and start empty.
            try? FileManager.default.moveItem(
                at: fileURL,
                to: fileURL.deletingLastPathComponent().appendingPathComponent("passes.corrupt.json"))
            passes = []
        }
    }

    private func save() {
        do {
            let data = try Self.makeEncoder().encode(passes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }
}
