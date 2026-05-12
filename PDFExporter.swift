import WebKit
import AppKit
import PDFKit

// MARK: - Public Entry Point

enum PDFExporter {
    static func export(html: String, headings: [Heading] = [], to outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                let task = RenderTask(html: html, headings: headings, outputURL: outputURL, continuation: cont)
                task.start()
            }
        }
    }
}

// MARK: - Render Task

private var _activeTask: RenderTask?

private final class RenderTask: NSObject, WKNavigationDelegate {
    let html: String
    let headings: [Heading]
    let outputURL: URL
    var continuation: CheckedContinuation<Void, Error>
    var webView: WKWebView?
    var window: NSWindow?

    init(html: String, headings: [Heading], outputURL: URL, continuation: CheckedContinuation<Void, Error>) {
        self.html = html
        self.headings = headings
        self.outputURL = outputURL
        self.continuation = continuation
    }

    func start() {
        _activeTask = self

        // WebView 宽度 = 打印内容区宽度（纸张 - 左右边距），消除缩放引起的跨机器偏移
        let printableWidth: CGFloat = 595.28 - 15 - 15  // 565.28pt
        let frame = NSRect(x: 0, y: 0, width: printableWidth, height: 842)
        let win = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: printableWidth, height: 842),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        win.isReleasedWhenClosed = false
        win.backgroundColor = .white

        let wv = WKWebView(frame: frame)
        wv.navigationDelegate = self
        win.contentView = wv
        // WKWebView 必须在已 ordered-in 的 window 里才会触发 didFinish
        // alphaValue=0 使其对用户不可见
        win.alphaValue = 0
        win.orderFrontRegardless()

        webView = wv
        window = win
        wv.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 等待图片/字体渲染完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.printToPDF()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    // MARK: - PDF via printOperation（真正 A4 分页，CSS page-break 生效）

    private func printToPDF() {
        guard let wv = webView, let win = window else {
            finish(.failure(ExportError.webViewGone)); return
        }

        let info = NSPrintInfo()
        // A4 in points (72 pt/inch): 595.28 × 841.89
        info.paperSize    = NSSize(width: 595.28, height: 841.89)
        info.topMargin    = 28
        info.bottomMargin = 28
        info.leftMargin   = 15
        info.rightMargin  = 15
        info.isHorizontallyCentered = false
        info.isVerticallyCentered   = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = outputURL as NSURL

        let op = wv.printOperation(with: info)
        op.showsPrintPanel    = false
        op.showsProgressPanel = false

        // 异步执行，不阻塞主线程（op.run() 会锁死 UI）
        op.runModal(for: win, delegate: self,
                    didRun: #selector(printOpDidRun(_:success:contextInfo:)),
                    contextInfo: nil)
    }

    @objc private func printOpDidRun(_ op: NSPrintOperation, success: Bool,
                                     contextInfo: UnsafeMutableRawPointer?) {
        // NSPrintOperation may invoke this callback on a background thread (macOS 26+).
        // All UI teardown (window?.close) must happen on the main thread.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard success else { self.finish(.failure(ExportError.printFailed)); return }

            if !self.headings.isEmpty,
               let data = try? Data(contentsOf: self.outputURL) {
                let patched = self.addPDFOutline(to: data, headings: self.headings)
                try? patched.write(to: self.outputURL, options: .atomic)
            }

            self.finish(.success(()))
        }
    }

    // MARK: - PDF Outline (Bookmarks)

    private func addPDFOutline(to data: Data, headings: [Heading]) -> Data {
        guard !headings.isEmpty,
              let doc = PDFDocument(data: data) else { return data }

        let root = PDFOutline()
        doc.outlineRoot = root

        // 从第 1 页开始搜（跳过第 0 页目录）
        var searchStart = 1

        for (i, heading) in headings.enumerated() {
            guard !heading.text.isEmpty else { continue }

            // 优先搜 "CHAPTER 01" 这类纯 ASCII 固定格式（不受字体/中文影响）
            // 找不到时再回退到标题文字
            let chapterLabel = String(format: "CHAPTER %02d", i + 1)
            let candidates   = [chapterLabel, heading.text]

            var target: PDFSelection?
            outer: for query in candidates {
                let matches = doc.findString(query, withOptions: [.caseInsensitive])
                for m in matches {
                    guard let page = m.pages.first else { continue }
                    let idx = doc.index(for: page)
                    guard idx >= searchStart else { continue }
                    target = m
                    searchStart = idx
                    break outer
                }
            }
            guard let sel = target, let page = sel.pages.first else { continue }

            let bounds = sel.bounds(for: page)
            let dest   = PDFDestination(page: page, at: CGPoint(x: 0, y: bounds.maxY + 6))

            let item = PDFOutline()
            item.label = heading.text   // 书签面板显示真实标题
            item.destination = dest
            item.isOpen = true

            root.insertChild(item, at: root.numberOfChildren)
        }

        return doc.dataRepresentation() ?? data
    }

    // MARK: - Cleanup

    private func finish(_ result: Result<Void, Error>) {
        window?.close(); window = nil; webView = nil; _activeTask = nil
        switch result {
        case .success:        continuation.resume()
        case .failure(let e): continuation.resume(throwing: e)
        }
    }
}

private enum ExportError: LocalizedError {
    case webViewGone
    case printFailed
    var errorDescription: String? {
        switch self {
        case .webViewGone:  return "内部错误：渲染器意外释放"
        case .printFailed:  return "PDF 导出失败"
        }
    }
}
