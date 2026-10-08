import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var project: Project

    private enum Mode: String, CaseIterable { case model = "3D 白模", plan = "平面图" }
    private enum Tool { case inspect, measure, note }

    @State private var mode: Mode = .model
    @State private var tool: Tool = .inspect
    @State private var showCeiling = false
    @State private var showFixtures = false
    @State private var showDimensions = true
    @State private var showPhotos = false
    @State private var showGallery = false
    @State private var viewingPhoto: FloorPlanData.SitePhoto?
    @State private var selectedRoomId: String?
    @State private var selectedWallId: String?
    @State private var measureStart: Vec3?
    @State private var editingAnnotation: FloorPlanData.Annotation?
    @State private var showExport = false

    @State private var showMeasuredAlert = false
    @State private var measuredInput = ""
    @State private var renamingRoomId: String?
    @State private var renameText = ""
    @State private var showRenameProject = false

    init(project: Project) {
        _project = State(initialValue: project)
        switch DemoMode.screen {
        case "model": _selectedRoomId = State(initialValue: project.plan.rooms.first?.id)
        case "plan": _mode = State(initialValue: .plan)
        default: break
        }
    }

    private var plan: FloorPlanData { project.plan }

    private var viewOptions: ViewOptions {
        ViewOptions(showCeiling: showCeiling, showFixtures: showFixtures, showDimensions: showDimensions,
                    selectedRoomId: selectedRoomId, selectedWallId: selectedWallId, pendingPoint: measureStart,
                    showPhotos: showPhotos)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("视图", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            roomChips

            ZStack(alignment: .bottom) {
                switch mode {
                case .model:
                    ModelViewer(plan: plan, options: viewOptions, onTap: handleHit)
                case .plan:
                    FloorPlanView(plan: plan, highlightRoomId: selectedRoomId)
                }
                VStack(spacing: 8) {
                    if mode == .model, let hint { hintBubble(hint) }
                    if let wall = selectedWall { wallCard(wall) }
                }
                .padding()
            }

            if mode == .model { toolBar }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重命名户型", systemImage: "pencil") {
                        renameText = project.name
                        showRenameProject = true
                    }
                    Button("现场照片（\(plan.sitePhotos.count)）", systemImage: "photo.on.rectangle") { showGallery = true }
                    Button("导出给 AI", systemImage: "square.and.arrow.up") { showExport = true }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showGallery) {
            SitePhotoGallery(projectId: project.id, plan: plan, onDelete: deleteSitePhoto)
        }
        .sheet(item: $viewingPhoto) { photo in
            NavigationStack {
                SitePhotoViewer(projectId: project.id, photo: photo, plan: plan, onDelete: deleteSitePhoto)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { viewingPhoto = nil }
                        }
                    }
            }
        }
        .sheet(item: $editingAnnotation) { ann in
            AnnotationSheet(projectId: project.id, annotation: ann,
                            isNew: !plan.annotations.contains { $0.id == ann.id },
                            onSave: saveAnnotation, onDelete: { deleteAnnotation(ann.id) })
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(project: project)
        }
        .alert("填写实测长度", isPresented: $showMeasuredAlert) {
            TextField("单位 mm，例如 4180", text: $measuredInput)
                .keyboardType(.numberPad)
            Button("保存") { saveMeasured() }
            if selectedWall?.measuredLength != nil {
                Button("清除实测值", role: .destructive) { setMeasured(nil) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("用卷尺量到的墙长。模型不会变，导出时会把扫描值和实测值一起给 AI，并告诉它优先用实测值。")
        }
        .alert("重命名房间", isPresented: Binding(get: { renamingRoomId != nil }, set: { if !$0 { renamingRoomId = nil } })) {
            TextField("房间名", text: $renameText)
            Button("保存") { renameRoom() }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名户型", isPresented: $showRenameProject) {
            TextField("户型名", text: $renameText)
            Button("保存") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                project.name = name
                project.plan.meta.projectName = name
                persist()
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            guard let screen = DemoMode.screen else { return }
            try? await Task.sleep(for: .milliseconds(800))
            if screen == "note" { editingAnnotation = plan.annotations.first }
            if screen == "export" { showExport = true }
        }
        .onChange(of: tool) { _, _ in
            measureStart = nil
            selectedWallId = nil
        }
    }

    // MARK: - 房间切换

    private var roomChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", selected: selectedRoomId == nil) { selectedRoomId = nil }
                ForEach(plan.rooms) { room in
                    chip("\(room.name) \(Fmt.area(room.area))㎡", selected: selectedRoomId == room.id) {
                        selectedRoomId = selectedRoomId == room.id ? nil : room.id
                    }
                    .contextMenu {
                        Button("重命名", systemImage: "pencil") {
                            renameText = room.name
                            renamingRoomId = room.id
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部工具栏

    private var toolBar: some View {
        HStack {
            toolButton("尺寸", "ruler", .inspect)
            toolButton("测距", "ruler.fill", .measure)
            toolButton("备注", "mappin.and.ellipse", .note)
            Menu {
                Toggle("尺寸标签", isOn: $showDimensions)
                Toggle("天花板", isOn: $showCeiling)
                Toggle("固定设施（水电位参考）", isOn: $showFixtures)
                Toggle("现场照片位置（\(plan.sitePhotos.count)）", isOn: $showPhotos)
            } label: {
                toolLabel("图层", "square.3.layers.3d", active: false)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func toolButton(_ title: String, _ icon: String, _ t: Tool) -> some View {
        Button { tool = t } label: { toolLabel(title, icon, active: tool == t) }
            .frame(maxWidth: .infinity)
    }

    private func toolLabel(_ title: String, _ icon: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2)
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    private var hint: String? {
        switch tool {
        case .inspect: return selectedWallId == nil ? "点墙查看尺寸、填实测值；点蓝色图钉看备注。单位 mm" : nil
        case .measure: return measureStart == nil ? "测距：点第一个点" : "测距：再点第二个点"
        case .note: return "点模型上的位置添加备注（可以附照片）"
        }
    }

    private func hintBubble(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }

    // MARK: - 选中的墙

    private var selectedWall: FloorPlanData.Wall? {
        selectedWallId.flatMap { plan.wall($0) }
    }

    private func wallCard(_ wall: FloorPlanData.Wall) -> some View {
        let rooms = wall.roomIds.compactMap { plan.room($0)?.name }.joined(separator: " / ")
        let openings = plan.openings(on: wall.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("墙 \(wall.id)").font(.headline)
                Text(rooms).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    selectedWallId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("关闭")
            }
            Text("扫描长度 \(Fmt.mm(wall.length)) · 高 \(Fmt.mm(wall.height))\(wall.isCurved ? " · 弧形墙（近似）" : "")")
                .font(.subheadline)
            if !openings.isEmpty {
                Text(openings.map { "\($0.kind == .door ? "门" : $0.kind == .window ? "窗" : "洞口") \(Fmt.mm($0.width))×\(Fmt.mm($0.height))" }
                    .joined(separator: "，"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(wall.measuredLength.map { "实测 \(Fmt.mm($0))" } ?? "还没有实测值")
                    .font(.subheadline)
                    .foregroundStyle(wall.measuredLength == nil ? .secondary : .primary)
                Spacer()
                Button(wall.measuredLength == nil ? "填实测值" : "修改实测值") {
                    measuredInput = wall.measuredLength.map(Fmt.mm) ?? ""
                    showMeasuredAlert = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 点击处理

    private func handleHit(_ hit: ViewerHit) {
        if case .annotation(let id) = hit {
            editingAnnotation = plan.annotations.first { $0.id == id }
            return
        }
        if case .photo(let id) = hit {
            viewingPhoto = plan.sitePhotos.first { $0.id == id }
            return
        }
        switch tool {
        case .inspect:
            if case .wall(let id, _) = hit {
                selectedWallId = selectedWallId == id ? nil : id
            } else {
                selectedWallId = nil
            }
        case .measure:
            guard let p = point(of: hit) else { return }
            if let a = measureStart {
                let ann = FloorPlanData.Annotation(
                    id: UUID().uuidString, number: plan.nextAnnotationNumber, kind: .measurement, text: "",
                    position: a, endPosition: p, distance: (p - a).length, photos: [],
                    cameraPosition: nil, cameraDirection: nil, createdAt: Date())
                project.plan.annotations.append(ann)
                measureStart = nil
                persist()
            } else {
                measureStart = p
            }
        case .note:
            guard let p = point(of: hit) else { return }
            editingAnnotation = FloorPlanData.Annotation(
                id: UUID().uuidString, number: plan.nextAnnotationNumber, kind: .note, text: "",
                position: p, endPosition: nil, distance: nil, photos: [],
                cameraPosition: nil, cameraDirection: nil, createdAt: Date())
        }
    }

    private func point(of hit: ViewerHit) -> Vec3? {
        switch hit {
        case .wall(_, let p), .surface(let p): return p
        default: return nil
        }
    }

    // MARK: - 保存

    private func persist() {
        project.updatedAt = Date()
        store.save(project)
    }

    private func saveAnnotation(_ ann: FloorPlanData.Annotation, newImages: [UIImage]) {
        var ann = ann
        for img in newImages {
            if let rel = try? store.savePhoto(img, projectId: project.id) { ann.photos.append(rel) }
        }
        if let i = project.plan.annotations.firstIndex(where: { $0.id == ann.id }) {
            project.plan.annotations[i] = ann
        } else {
            project.plan.annotations.append(ann)
        }
        persist()
    }

    private func deleteSitePhoto(_ id: String) {
        guard let photo = plan.sitePhotos.first(where: { $0.id == id }) else { return }
        project.plan.sitePhotos.removeAll { $0.id == id }
        // 备注里没再用到这张照片，就把文件也删掉
        if !project.plan.annotations.contains(where: { $0.photos.contains(photo.path) }) {
            try? FileManager.default.removeItem(at: store.photoURL(projectId: project.id, relativePath: photo.path))
        }
        persist()
    }

    private func deleteAnnotation(_ id: String) {
        project.plan.annotations.removeAll { $0.id == id }
        persist()
    }

    private func saveMeasured() {
        let digits = measuredInput.filter(\.isNumber)
        guard let mm = Double(digits), mm > 0 else { return }
        setMeasured(mm / 1000)
    }

    private func setMeasured(_ meters: Double?) {
        guard let id = selectedWallId, let i = project.plan.walls.firstIndex(where: { $0.id == id }) else { return }
        project.plan.walls[i].measuredLength = meters
        persist()
    }

    private func renameRoom() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard let id = renamingRoomId, !name.isEmpty,
              let i = project.plan.rooms.firstIndex(where: { $0.id == id }) else { return }
        project.plan.rooms[i].name = name
        renamingRoomId = nil
        persist()
    }
}
