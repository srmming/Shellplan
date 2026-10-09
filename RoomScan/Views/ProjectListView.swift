import RoomPlan
import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var path: [UUID] = []
    @State private var showScanner = false
    @State private var pendingDelete: Project?
    @State private var showOnboarding = false
    @AppStorage("didShowOnboarding") private var didShowOnboarding = false

    private let scanSupported = RoomCaptureSession.isSupported

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("扫描你的第一个户型", systemImage: "cube.transparent")
                    } description: {
                        Text("用 LiDAR 一个房间一个房间地扫，自动拼成全屋白模，并标好尺寸。")
                    }
                } else {
                    List {
                        ForEach(store.projects) { project in
                            NavigationLink(value: project.id) {
                                ProjectRow(project: project)
                            }
                            .swipeActions {
                                Button("删除") { pendingDelete = project }
                                    .tint(.red)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("我的户型")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("加载示例户型", systemImage: "square.stack.3d.up") { loadSample() }
                        Button("使用说明", systemImage: "questionmark.circle") { showOnboarding = true }
                        Link(destination: URL(string: "https://github.com/srmming/Roomprint/issues")!) {
                            Label("反馈问题", systemImage: "exclamationmark.bubble")
                        }
                        Link(destination: URL(string: "https://github.com/srmming/Roomprint")!) {
                            Label("源代码（开源）", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { scanBar }
            .navigationDestination(for: UUID.self) { id in
                if let project = store.project(id) {
                    ProjectDetailView(project: project)
                } else {
                    Text("这个户型已经不存在了")
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                didShowOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            if let screen = DemoMode.screen {
                if ["model", "plan", "note", "export", "door"].contains(screen), let first = store.projects.first {
                    path = [first.id]
                }
            } else if !didShowOnboarding {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScanScreen(projectName: defaultProjectName) { output in
                let project = store.createProject(from: output)
                showScanner = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { path.append(project.id) }
            }
        }
        .alert("删除这个户型？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { project in
            Button("删除", role: .destructive) { store.delete(project) }
            Button("取消", role: .cancel) {}
        } message: { project in
            Text("「\(project.name)」的模型、标注和照片都会被删除，无法恢复。")
        }
    }

    private var scanBar: some View {
        VStack(spacing: 8) {
            Button {
                showScanner = true
            } label: {
                Label("开始扫描", systemImage: "viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!scanSupported)

            Text(scanSupported ? String(localized: "一个房间一个房间扫，最后自动拼成全屋") : String(localized: "这台设备没有 LiDAR，不能扫描。可以先从右上角加载示例户型看看效果"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.bar)
    }

    private var defaultProjectName: String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        return String(localized: "我的户型 \(df.string(from: Date()))")
    }

    private func loadSample() {
        let now = Date()
        let project = Project(id: UUID(), name: String(localized: "示例户型"), createdAt: now, updatedAt: now, plan: SampleData.plan())
        store.save(project)
        path.append(project.id)
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.headline)
                Text("\(project.plan.rooms.count) 个房间 · \(Fmt.area(project.plan.totalArea)) ㎡ · 层高 \(String(format: "%.2f", project.plan.maxHeight))m")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(project.updatedAt.formatted(date: .abbreviated, time: .omitted)) · \(project.plan.annotations.count) 条标注 · \(project.photoCount) 张照片")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
