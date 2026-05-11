import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            mainArea
            Divider()
            bottomBar
        }
        .frame(width: 540)
        .alert("转换完成", isPresented: $vm.showSuccess) {
            Button("在 Finder 中显示") { vm.revealInFinder() }
            Button("确定") {}
        } message: {
            Text("PDF 已保存到: \(vm.outputURL?.lastPathComponent ?? "")")
        }
        .alert("转换失败", isPresented: $vm.showError) {
            Button("确定") {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - Main Area

    @ViewBuilder
    private var mainArea: some View {
        if vm.mdFiles.isEmpty {
            dropZone
        } else {
            fileListView
        }
    }

    // MARK: - Empty: Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: vm.isDragging ? [] : [8, 4])
                )
                .foregroundColor(vm.isDragging ? .accentColor : Color.secondary.opacity(0.35))
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(vm.isDragging
                              ? Color.accentColor.opacity(0.07)
                              : Color(NSColor.windowBackgroundColor))
                )
                .animation(.easeInOut(duration: 0.15), value: vm.isDragging)

            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(vm.isDragging
                                     ? .accentColor
                                     : Color.secondary.opacity(0.5))
                VStack(spacing: 4) {
                    Text("将 Markdown 文件夹拖到这里")
                        .font(.headline)
                    Text("自动处理文件夹内的相对路径图片")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Button("选择文件夹…") { vm.pickFolder() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
            .padding(36)
        }
        .padding(20)
        .onDrop(of: [.fileURL], isTargeted: $vm.isDragging) { providers in
            vm.handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Loaded: File List

    private var fileListView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.folderURL?.lastPathComponent ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(vm.mdFiles.count) 个文件 · 拖动行可排序")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !vm.isConverting {
                    Button("重新选择") { vm.reset() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                ForEach(Array(vm.mdFiles.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(url.lastPathComponent)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(Color.secondary.opacity(0.4))
                    }
                    .padding(.vertical, 3)
                    .padding(.trailing, 16)
                }
                .onMove { from, to in vm.mdFiles.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: min(CGFloat(vm.mdFiles.count) * 35 + 2, 280))
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            vm.handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if vm.isConverting {
                VStack(spacing: 6) {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            HStack {
                Spacer()
                Button("开始转换") { vm.startConversion() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.mdFiles.isEmpty || vm.isConverting)
            }
            .padding(.horizontal, 16)
            .padding(.top, vm.isConverting ? 4 : 14)
            .padding(.bottom, 16)
        }
    }
}
