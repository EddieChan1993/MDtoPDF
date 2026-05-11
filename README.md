# GrapePress

A macOS app that converts a folder of Markdown files into a paginated A4 PDF ebook — with a table of contents, chapter page breaks, PDF bookmarks, and embedded images.

## Features

- Drag & drop a folder containing `.md` files
- Reorder chapters by dragging rows in the file list
- Embeds local images (relative paths, including `../../` traversal) as base64
- Compresses images to max 1000 px wide, JPEG 0.72 — keeps PDF size reasonable
- Generates a TOC page (chapter names only)
- Each chapter starts on a new A4 page with a chapter header
- PDF bookmarks panel synced to chapter list
- True A4 pagination via `NSPrintOperation` (not a long strip)

## Requirements

- macOS 13.0+
- Xcode Command Line Tools (`xcode-select --install`)
- For icon generation: `brew install librsvg`

## Build

```bash
# Generate app icon (requires librsvg)
python3 make_icon.py

# Build and package MDtoPDF.app
bash build.sh
```

The script compiles with Swift Package Manager, assembles `MDtoPDF.app`, copies the icon, and ad-hoc codesigns.

If macOS shows "unverified developer" on first launch:
- Right-click → Open → click Open, **or**
- `xattr -cr MDtoPDF.app`

## Usage

1. Launch `MDtoPDF.app`
2. Drag a folder of `.md` files onto the drop zone
3. Reorder chapters if needed (drag rows)
4. Click **开始转换**, choose a save location
5. The PDF is saved with TOC, chapter breaks, and bookmarks

## Project Structure

```
MDtoPDF/
├── MDtoPDFApp.swift      # App entry point
├── ContentView.swift     # SwiftUI UI
├── AppViewModel.swift    # State + conversion orchestration
├── MarkdownParser.swift  # Line-by-line MD parser, HTML builder
├── PDFExporter.swift     # WKWebView render → NSPrintOperation → PDF
├── make_icon.py          # Generates AppIcon.icns from SVG
├── build.sh              # Build + package script
└── Info.plist            # Bundle metadata
```

## Icon

Flat design: deep purple background, lavender grape clusters, green leaves labeled **MD** and **PDF**.  
Generated from `make_icon.py` via `rsvg-convert` + `iconutil`.
