import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
class AppViewModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var mdFiles: [URL] = []
    @Published var isDragging = false
    @Published var history: [URL] = []

    private let historyKey = "folderHistory"
    @Published var isConverting = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var showSuccess = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var outputURL: URL?

    private var conversionTask: Task<Void, Never>?

    init() { loadHistory() }

    // MARK: - History

    private func loadHistory() {
        let paths = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        history = paths.compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func saveHistory() {
        UserDefaults.standard.set(history.map(\.path), forKey: historyKey)
    }

    func addToHistory(_ url: URL) {
        history.removeAll { $0 == url }
        history.insert(url, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        saveHistory()
    }

    func removeFromHistory(_ url: URL) {
        history.removeAll { $0 == url }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    // MARK: - Drop

    func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        // 直接在主线程上调用 loadItem，回调里再跳回 MainActor
        // 避免把非 Sendable 的 NSItemProvider 传入 Task / nonisolated 函数
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, _ in
            var resolved: URL?
            if let u = item as? URL { resolved = u }
            else if let d = item as? Data { resolved = URL(dataRepresentation: d, relativeTo: nil) }
            guard let url = resolved else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            Task { @MainActor [weak self] in self?.loadFolder(url) }
        }
    }

    func loadFolder(_ url: URL) {
        folderURL = url
        addToHistory(url)
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
        ) else { return }
        mdFiles = items
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Actions

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择包含 Markdown 文件的文件夹"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFolder(url)
    }

    func reset() {
        folderURL = nil
        mdFiles = []
        isConverting = false
        progress = 0
        statusMessage = ""
        outputURL = nil
    }

    func revealInFinder() {
        guard let url = outputURL else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }

    func startConversion() {
        guard !mdFiles.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (folderURL?.lastPathComponent ?? "output") + ".pdf"
        panel.message = "选择 PDF 保存位置"
        guard panel.runModal() == .OK, let saveURL = panel.url else { return }
        outputURL = saveURL
        isConverting = true
        progress = 0
        statusMessage = "准备中..."
        conversionTask = Task { await convert(to: saveURL) }
    }

    func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
        isConverting = false
        progress = 0
        statusMessage = ""
    }

    // MARK: - Conversion

    private func convert(to saveURL: URL) async {
        let files = mdFiles
        let total = Double(files.count)
        var chapters: [Chapter] = []

        for (i, fileURL) in files.enumerated() {
            guard !Task.isCancelled else { cancelConversion(); return }

            statusMessage = "解析: \(fileURL.lastPathComponent)"
            progress = Double(i) / total * 0.75

            guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
                statusMessage = "跳过（读取失败）: \(fileURL.lastPathComponent)"
                continue
            }

            let baseDir = fileURL.deletingLastPathComponent()
            let title = fileURL.deletingPathExtension().lastPathComponent
            let anchorID = "chapter-\(i)"

            let result = await Task.detached(priority: .userInitiated) {
                MarkdownParser.parse(raw, baseDirectory: baseDir)
            }.value

            chapters.append(Chapter(title: title, anchorID: anchorID,
                                    html: result.html, headings: result.headings))
        }

        guard !Task.isCancelled else { cancelConversion(); return }

        statusMessage = "渲染中，生成 PDF..."
        progress = 0.85

        let fullHTML = MarkdownParser.buildPage(chapters: chapters)

        // 书签面板只用章节标题（一级），不混入文内 heading
        let outlineHeadings = chapters.enumerated().map { i, ch in
            Heading(level: 1, text: ch.title, id: ch.anchorID)
        }

        do {
            statusMessage = "导出 PDF..."
            progress = 0.92
            try await PDFExporter.export(html: fullHTML, headings: outlineHeadings, to: saveURL)
            guard !Task.isCancelled else { cancelConversion(); return }
            progress = 1.0
            statusMessage = "完成！"
            isConverting = false
            showSuccess = true
        } catch {
            guard !Task.isCancelled else { cancelConversion(); return }
            isConverting = false
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
