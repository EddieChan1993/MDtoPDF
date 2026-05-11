import Foundation
import AppKit

// MARK: - Public Types

struct Heading {
    let level: Int
    let text: String
    let id: String
}

struct Chapter {
    let title: String       // 文件名（去掉 .md 后缀）
    let anchorID: String    // 章节锚点，用于目录跳转
    let html: String
    let headings: [Heading]
}

// MARK: - Public API

enum MarkdownParser {

    static func parse(_ markdown: String, baseDirectory: URL) -> (html: String, headings: [Heading]) {
        var parser = Parser(baseDirectory: baseDirectory)
        let html = parser.convert(markdown)
        return (html, parser.headings)
    }

    static func buildPage(chapters: [Chapter]) -> String {
        let toc = generateTOC(chapters: chapters)

        let body = chapters.enumerated().map { i, ch in
            // 第一章不加 page-break-before，其余章节强制新页
            let breakStyle = i == 0 ? "" : " style=\"page-break-before:always;\""
            let chapterNum = String(format: "CHAPTER %02d", i + 1)
            return """
            <section class="chapter"\(breakStyle)>
              <div id="\(ch.anchorID)" class="chapter-label">\(chapterNum)</div>
              <div class="chapter-title-bar">\(ch.title)</div>
            \(ch.html)
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="UTF-8">
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(toc)
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - TOC Page

    private static func generateTOC(chapters: [Chapter]) -> String {
        guard !chapters.isEmpty else { return "" }

        var items = ""
        for (i, ch) in chapters.enumerated() {
            let num = String(format: "%02d", i + 1)
            items += "<div class=\"toc-chapter\"><a href=\"#\(ch.anchorID)\"><span class=\"toc-chapter-num\">\(num)</span>\(ch.title)</a></div>\n"
        }

        return """
        <section class="toc-page" style="page-break-after:always;">
          <h1 class="toc-title">目&ensp;录</h1>
          <div class="toc-list">
        \(items)
          </div>
        </section>
        """
    }
}

// MARK: - Parser

private struct Parser {
    let baseDirectory: URL

    var output = ""
    var listBuffer = ""
    var inUL = false
    var inOL = false
    var inCodeBlock = false
    var codeLang = ""
    var codeLines: [String] = []
    var inTable = false
    var tableRows: [String] = []
    var tableHasHeader = false

    var headings: [Heading] = []
    var headingIDCounters: [String: Int] = [:]

    mutating func convert(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")

        for line in lines {
            if inCodeBlock {
                if line.hasPrefix("```") { flushCode() }
                else { codeLines.append(line) }
                continue
            }

            if line.hasPrefix("```") {
                flushList(); flushTable()
                codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                inCodeBlock = true
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                flushList(); flushTable()
                output += "\n"
                continue
            }

            // Table
            if trimmed.hasPrefix("|") {
                if isSeparatorRow(trimmed) { tableHasHeader = true }
                else { tableRows.append(trimmed) }
                inTable = true
                continue
            } else if inTable {
                flushTable()
            }

            // Headers
            if let (level, text) = parseHeader(trimmed) {
                flushList()
                let id = makeHeadingID(text)
                headings.append(Heading(level: level, text: text, id: id))
                output += "<h\(level) id=\"\(id)\">\(inline(text))</h\(level)>\n"
                continue
            }

            // Horizontal rule
            if (trimmed == "---" || trimmed == "***" || trimmed == "___") ||
               (trimmed.allSatisfy({ $0 == "-" }) && trimmed.count >= 3) {
                flushList()
                output += "<hr>\n"
                continue
            }

            // Blockquote — handles ">", "> text", "> ## heading"
            if trimmed.hasPrefix(">") {
                flushList(); flushTable()
                let after = trimmed.dropFirst(1)
                let content = after.hasPrefix(" ") ? String(after.dropFirst(1)) : String(after)
                if content.isEmpty {
                    // 单独的 ">" 行作为空白间隔，静默跳过
                } else if let (level, headingText) = parseHeader(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let id = makeHeadingID(headingText)
                    headings.append(Heading(level: level, text: headingText, id: id))
                    output += "<blockquote><h\(level) id=\"\(id)\">\(inline(headingText))</h\(level)></blockquote>\n"
                } else {
                    output += "<blockquote><p>\(inline(content))</p></blockquote>\n"
                }
                continue
            }

            // Unordered list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                if inOL { flushList() }
                inUL = true
                listBuffer += "<li>\(inline(String(trimmed.dropFirst(2))))</li>\n"
                continue
            }

            // Ordered list
            if let r = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                if inUL { flushList() }
                inOL = true
                listBuffer += "<li>\(inline(String(trimmed[r.upperBound...])))</li>\n"
                continue
            }

            // Paragraph
            flushList()
            output += "<p>\(inline(trimmed))</p>\n"
        }

        flushList(); flushTable()
        if inCodeBlock { flushCode() }
        return output
    }

    // MARK: - Flush Helpers

    mutating func flushList() {
        guard !listBuffer.isEmpty else { return }
        if inUL { output += "<ul>\n\(listBuffer)</ul>\n" }
        else if inOL { output += "<ol>\n\(listBuffer)</ol>\n" }
        listBuffer = ""; inUL = false; inOL = false
    }

    mutating func flushCode() {
        let escaped = escapeHTML(codeLines.joined(separator: "\n"))
        let cls = codeLang.isEmpty ? "" : " class=\"language-\(codeLang)\""
        output += "<pre><code\(cls)>\(escaped)</code></pre>\n"
        codeLines = []; codeLang = ""; inCodeBlock = false
    }

    mutating func flushTable() {
        guard inTable, !tableRows.isEmpty else {
            inTable = false; tableRows = []; tableHasHeader = false; return
        }
        output += "<table>\n"
        for (i, row) in tableRows.enumerated() {
            let cells = row.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst().dropLast()
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            if i == 0 && tableHasHeader {
                output += "<thead><tr>" + cells.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead>\n<tbody>\n"
            } else {
                output += "<tr>" + cells.map { "<td>\(inline($0))</td>" }.joined() + "</tr>\n"
            }
        }
        if tableHasHeader { output += "</tbody>\n" }
        output += "</table>\n"
        tableRows = []; tableHasHeader = false; inTable = false
    }

    // MARK: - Inline Parsing

    func inline(_ text: String) -> String {
        var s = embedImages(text)
        s = s.replacingOccurrences(of: #"~~(.+?)~~"#,          with: "<del>$1</del>",             options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,     with: "<strong>$1</strong>",        options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#,          with: "<strong>$1</strong>",        options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*(.+?)\*"#,          with: "<em>$1</em>",               options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![_])_([^_]+)_(?![_])"#, with: "<em>$1</em>",         options: .regularExpression)
        s = s.replacingOccurrences(of: #"`([^`]+)`"#,          with: "<code>$1</code>",            options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return s
    }

    func embedImages(_ text: String) -> String {
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = ""
        var lastEnd = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let fullRange = Range(match.range, in: text),
                  let altRange  = Range(match.range(at: 1), in: text),
                  let pathRange = Range(match.range(at: 2), in: text) else { continue }
            result += text[lastEnd ..< fullRange.lowerBound]
            lastEnd = fullRange.upperBound
            let alt  = escapeAttr(String(text[altRange]))
            let path = String(text[pathRange])
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                result += "<img src=\"\(path)\" alt=\"\(alt)\">"
            } else {
                let decoded = path.removingPercentEncoding ?? path
                let imageURL = baseDirectory.appendingPathComponent(decoded).standardized
                if let (data, mime) = compressImage(at: imageURL) {
                    result += "<img src=\"data:\(mime);base64,\(data.base64EncodedString())\" alt=\"\(alt)\">"
                } else {
                    result += "<span class=\"img-missing\">[图片未找到: \(path)]</span>"
                }
            }
        }
        result += text[lastEnd...]
        return result
    }

    // MARK: - Utilities

    func parseHeader(_ line: String) -> (Int, String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" && level < 6 {
            level += 1; idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex,
              line[idx] == " " || line[idx] == "\t" else { return nil }
        let text = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (level, text)
    }

    mutating func makeHeadingID(_ text: String) -> String {
        var base = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber { base.append(ch) }
            else if ch == " " || ch == "-" { base.append("-") }
        }
        if base.isEmpty { base = "h" }
        // Remove consecutive dashes
        while base.contains("--") { base = base.replacingOccurrences(of: "--", with: "-") }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if base.isEmpty { base = "h" }
        let n = headingIDCounters[base, default: 0]
        headingIDCounters[base] = n + 1
        return n == 0 ? base : "\(base)-\(n)"
    }

    func isSeparatorRow(_ row: String) -> Bool {
        row.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
           .allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0 == " " }
    }

    func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    func escapeAttr(_ s: String) -> String {
        escapeHTML(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    func compressImage(at url: URL, maxWidth: CGFloat = 800) -> (Data, String)? {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" { return (try? Data(contentsOf: url)).map { ($0, "image/svg+xml") } }
        if ext == "gif" { return (try? Data(contentsOf: url)).map { ($0, "image/gif") } }

        guard let image = NSImage(contentsOf: url) else { return nil }
        let orig = image.size
        let scale: CGFloat = orig.width > maxWidth ? maxWidth / orig.width : 1.0
        let target = NSSize(width: orig.width * scale, height: orig.height * scale)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        if ext == "png" {
            return rep.representation(using: .png, properties: [:]).map { ($0, "image/png") }
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: 0.55)])
                  .map { ($0, "image/jpeg") }
    }
}

// MARK: - CSS

private let css = """
*, *::before, *::after { box-sizing: border-box; }
@page { size: A4; margin: 0; }
html, body { margin: 0; padding: 0; background: white; }
body {
    font-family: -apple-system, 'PingFang SC', 'Hiragino Sans GB', 'Helvetica Neue', Arial, sans-serif;
    font-size: 14px; line-height: 1.65; color: #111827;
}

/* ── TOC Page ── */
.toc-page { padding: 60px 70px 40px; min-height: 900px; }
.toc-title {
    text-align: center;
    font-size: 1.8em;
    letter-spacing: 0.7em;
    text-indent: 0.7em;
    margin-bottom: 36px;
    color: #1e1b4b;
    font-weight: 800;
}
.toc-list { font-size: 0.94em; }
.toc-chapter {
    margin-top: 14px;
    padding: 6px 0 4px;
    border-bottom: 1.5px solid #c7d2fe;
    font-weight: 700;
    font-size: 1em;
}
.toc-chapter:first-child { margin-top: 0; }
.toc-chapter a { text-decoration: none; color: #1e1b4b; display: flex; align-items: center; gap: 10px; }
.toc-chapter-num {
    font-size: 0.75em;
    color: #6366f1;
    font-weight: 600;
    letter-spacing: 0.08em;
    min-width: 2.2em;
}

/* ── Chapter Content ── */
.chapter { padding: 36px 60px; max-width: 794px; }

.chapter-label {
    font-size: 0.68em;
    font-weight: 700;
    letter-spacing: 0.2em;
    color: #6366f1;
    text-transform: uppercase;
    margin-bottom: 4px;
}
.chapter-title-bar {
    font-size: 1.7em;
    font-weight: 800;
    color: #1e1b4b;
    padding-bottom: 10px;
    margin-bottom: 22px;
    border-bottom: 3px solid #6366f1;
    line-height: 1.25;
}

/* 标题层级：颜色 + 大小形成清晰视觉层次 */
h1 {
    font-size: 1.75em; font-weight: 800; color: #1e1b4b;
    border-bottom: 2px solid #e0e7ff;
    padding-bottom: 0.25em; margin: 1.1em 0 0.5em;
}
h2 {
    font-size: 1.4em; font-weight: 700; color: #312e81;
    border-bottom: 1px solid #e0e7ff;
    padding-bottom: 0.2em; margin: 1em 0 0.45em;
}
h3 {
    font-size: 1.18em; font-weight: 700; color: #3730a3;
    margin: 0.9em 0 0.35em;
}
h4 { font-size: 1.05em; font-weight: 600; color: #4338ca; margin: 0.8em 0 0.3em; }
h5, h6 { font-size: 0.95em; font-weight: 600; color: #6366f1; margin: 0.7em 0 0.25em; }
h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }

p { margin: 7px 0; }
a { color: #4f46e5; text-decoration: none; }
strong { font-weight: 700; color: #111827; }

img {
    max-width: 100%; height: auto;
    display: block; margin: 12px auto; border-radius: 4px;
}

code {
    font-family: 'SF Mono', Menlo, 'Courier New', monospace;
    font-size: 0.86em; background: #f0f0ff;
    padding: 0.15em 0.4em; border-radius: 3px; color: #7c3aed;
}
pre {
    background: #1e1b2e; border: none;
    border-radius: 6px; padding: 14px 16px;
    margin: 12px 0; line-height: 1.55;
}
pre code {
    background: none; padding: 0;
    color: #e2e8f0; font-size: 0.84em;
}

blockquote {
    border-left: 4px solid #6366f1;
    background: #f5f3ff;
    color: #374151;
    margin: 10px 0;
    padding: 6px 14px;
    border-radius: 0 4px 4px 0;
}
blockquote p { margin: 3px 0; }
blockquote h1, blockquote h2, blockquote h3,
blockquote h4, blockquote h5, blockquote h6 {
    margin: 4px 0; border-bottom: none;
}

table {
    border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 0.91em;
}
th, td { border: 1px solid #e0e7ff; padding: 6px 12px; text-align: left; }
th { background: #eef2ff; font-weight: 700; color: #312e81; }
tr:nth-child(even) { background: #f9fafb; }

ul, ol { padding-left: 1.8em; margin: 7px 0; }
li { margin: 2px 0; }
hr { border: none; border-top: 1px solid #e0e7ff; margin: 18px 0; }
del { color: #9ca3af; }

.img-missing {
    color: #dc2626; font-size: 0.84em;
    background: #fee2e2; padding: 2px 6px; border-radius: 3px;
}

.page-break { page-break-after: always; break-after: page; height: 0; margin: 0; }

@media print {
    body { print-color-adjust: exact; -webkit-print-color-adjust: exact; font-size: 12pt; }
    .toc-page, .chapter { padding: 0; }
    section.chapter { page-break-before: always; break-before: page; }
    section.toc-page { page-break-after: always; break-after: page; }
}
"""
