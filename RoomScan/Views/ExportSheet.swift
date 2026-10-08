import SwiftUI

struct ExportSheet: View {
    let project: Project

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var isPacking = false
    @State private var zipURL: URL?
    @State private var showShare = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    item("cube", "白模 OBJ / USDA", "墙体已挖好门窗洞，Blender 可直接导入")
                    item("doc.richtext", "尺寸平面图 PNG / PDF", "单位 mm，含房间名、面积、门窗尺寸")
                    item("curlybraces", "scene.json 结构数据", "\(project.plan.rooms.count) 个房间 · \(project.plan.walls.count) 面墙 · \(project.plan.openings.count) 个门窗")
                    item("photo.on.rectangle", "照片 \(project.photoCount) 张", "带拍摄位置，对应到备注")
                    item("chevron.left.forwardslash.chevron.right", "Blender 重建脚本 + AI 说明", "build_whitebox.py · AI_README.md")
                } header: {
                    Text("导出包内容")
                } footer: {
                    Text("打包成一个 zip，用隔空投送发到 Mac，或者存到「文件」。把整个文件夹交给 AI，让它先读 AI_README.md。")
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    pack()
                } label: {
                    HStack {
                        if isPacking { ProgressView().tint(.white) }
                        Label(isPacking ? "正在打包…" : "打包分享", systemImage: "doc.zipper")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isPacking)
                .padding()
                .background(.bar)
            }
            .navigationTitle("导出给 AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                if let zipURL { ShareSheet(items: [zipURL]) }
            }
        }
    }

    private func item(_ icon: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private func pack() {
        isPacking = true
        errorText = nil
        let project = self.project
        let dir = store.directory(for: project.id)
        Task.detached(priority: .userInitiated) {
            do {
                let url = try ExportPackager.makePackage(project: project, projectDir: dir)
                await MainActor.run {
                    zipURL = url
                    isPacking = false
                    showShare = true
                }
            } catch {
                await MainActor.run {
                    errorText = "打包失败：\(error.localizedDescription)"
                    isPacking = false
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
