import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var project: Project

    private enum Mode: CaseIterable {
        case model, plan
        var title: String {
            switch self {
            case .model: return String(localized: "3D 白模")
            case .plan: return String(localized: "平面图")
            }
        }
    }
    private enum Tool { case inspect, measure, note }

    @State private var mode: Mode = .model
    @State private var tool: Tool = .inspect
    @State private var showCeiling = false
    @State private var showDimensions = true
    @State private var showPhotos = false
    @State private var showGallery = false
    @State private var viewingPhoto: FloorPlanData.SitePhoto?
    @State private var selectedRoomId: String?
    @State private var selectedWallId: String?
    /// 点墙时点到的位置，添加门窗时用来定初始位置
    @State private var selectedWallPoint: Vec2?
    @State private var editingOpening: FloorPlanData.Opening?
    @State private var editingColumn: FloorPlanData.Column?
    @State private var addingColumn = false
    @State private var cleanupMessage: String?
    @State private var confirmRestore = false
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
        case "plan", "door": _mode = State(initialValue: .plan)
        default: break
        }
    }

    private var plan: FloorPlanData { project.plan }

    private var viewOptions: ViewOptions {
        ViewOptions(showCeiling: showCeiling, showDimensions: showDimensions,
                    selectedRoomId: selectedRoomId, selectedWallId: selectedWallId, pendingPoint: measureStart,
                    showPhotos: showPhotos, selectedColumnId: editingColumn?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("视图", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.title) }
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
                    FloorPlanView(plan: plan, highlightRoomId: selectedRoomId, selectedOpeningId: editingOpening?.id,
                                  selectedWallId: selectedWallId, selectedColumnId: editingColumn?.id, onTap: handlePlanHit)
                }
                VStack(spacing: 8) {
                    if let hint { hintBubble(hint) }
                    if let wall = selectedWall { wallCard(wall) }
                }
                .padding()
            }

            if mode == .model { toolBar } else { planBar }
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
                    Button("自动整理墙体", systemImage: "wand.and.stars") { cleanupWalls() }
                    if hasCleanupBackup {
                        Button("恢复整理前的墙体", systemImage: "arrow.uturn.backward") { confirmRestore = true }
                    }
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
        .sheet(item: $editingOpening) { o in
            OpeningEditor(plan: plan, opening: o, isNew: plan.opening(o.id) == nil,
                          onSave: saveOpening, onDelete: { deleteOpening(o.id) })
        }
        .sheet(item: $editingColumn) { c in
            ColumnEditor(column: c, isNew: !plan.columns.contains { $0.id == c.id },
                         onSave: saveColumn, onDelete: { deleteColumn(c.id) })
        }
        .alert("墙体整理好了", isPresented: Binding(get: { cleanupMessage != nil }, set: { if !$0 { cleanupMessage = nil } })) {
            Button("好") {}
        } message: {
            Text(cleanupMessage ?? "")
        }
        .confirmationDialog("恢复到第一次整理之前？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("恢复", role: .destructive) { restoreWalls() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("整理之后改过的门窗、柱子和备注也会一起还原。")
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
            if screen == "door" { editingOpening = plan.opening("D2") ?? plan.openings.first }
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
                chip(String(localized: "全部"), selected: selectedRoomId == nil) { selectedRoomId = nil }
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

    /// 平面图底部：加柱子
    private var planBar: some View {
        HStack {
            Button {
                addingColumn.toggle()
                selectedWallId = nil
            } label: {
                toolLabel("加柱子", "square.dashed.inset.filled", active: addingColumn)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func toolButton(_ title: LocalizedStringKey, _ icon: String, _ t: Tool) -> some View {
        Button { tool = t } label: { toolLabel(title, icon, active: tool == t) }
            .frame(maxWidth: .infinity)
    }

    private func toolLabel(_ title: LocalizedStringKey, _ icon: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2)
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
    }

    private var hint: String? {
        if mode == .plan {
            if addingColumn { return String(localized: "点一下放一根柱子，点在墙边会自动贴墙") }
            return selectedWallId == nil ? String(localized: "点门窗、柱子可以修改；点墙可以添加门窗") : nil
        }
        switch tool {
        case .inspect: return selectedWallId == nil ? String(localized: "点墙查看尺寸、填实测值；点蓝色图钉看备注。单位 mm") : nil
        case .measure: return measureStart == nil ? String(localized: "测距：点第一个点") : String(localized: "测距：再点第二个点")
        case .note: return String(localized: "点模型上的位置添加备注（可以附照片）")
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
            Text("扫描长度 \(Fmt.mm(wall.length)) · 高 \(Fmt.mm(wall.height))") + Text(wall.isCurved ? String(localized: " · 弧形墙（近似）") : "")
                .font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(plan.columns.filter { $0.wallIds.contains(wall.id) }) { c in
                        Button(L10n.column(c), systemImage: "square.dashed.inset.filled") { editingColumn = c }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    ForEach(openings) { o in
                        Button("\(L10n.title(o)) \(Fmt.mm(o.width))×\(Fmt.mm(o.height))") { editingOpening = o }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("加门", systemImage: "plus") { addOpening(.door, on: wall) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("加窗", systemImage: "plus") { addOpening(.window, on: wall) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            HStack {
                Text(wall.measuredLength.map { String(localized: "实测 \(Fmt.mm($0))") } ?? String(localized: "还没有实测值"))
                    .font(.subheadline)
                    .foregroundStyle(wall.measuredLength == nil ? .secondary : .primary)
                Spacer()
                Button(wall.measuredLength == nil ? String(localized: "填实测值") : String(localized: "修改实测值")) {
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
        if case .column(let id, _) = hit {
            editingColumn = plan.columns.first { $0.id == id }
            return
        }
        switch tool {
        case .inspect:
            if case .wall(let id, let p) = hit {
                selectedWallPoint = p.xy
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

    private func handlePlanHit(_ hit: PlanHit) {
        if addingColumn {
            switch hit {
            case .floor(let p), .wall(_, let p):
                editingColumn = newColumn(at: p)
                addingColumn = false
                return
            default:
                break
            }
        }
        switch hit {
        case .column(let id):
            editingColumn = plan.columns.first { $0.id == id }
        case .floor:
            selectedWallId = nil
        case .opening(let id):
            editingOpening = plan.opening(id)
        case .wall(let id, let p):
            selectedWallPoint = p
            selectedWallId = selectedWallId == id ? nil : id
        case .nothing:
            selectedWallId = nil
        }
    }

    /// 在选中的墙上加一个门或窗，位置放在刚才点到的地方
    private func addOpening(_ kind: FloorPlanData.OpeningKind, on wall: FloorPlanData.Wall) {
        let width = kind == .door ? 0.9 : 1.2
        var center = wall.length / 2
        if let p = selectedWallPoint { center = (p - wall.start).dot(wall.direction) }
        center = min(max(center, width / 2), max(wall.length - width / 2, width / 2))
        editingOpening = FloorPlanData.Opening(
            id: "\(kind == .door ? "D" : "WIN")\(UUID().uuidString.prefix(4))", kind: kind, wallId: wall.id,
            centerOffset: center, width: min(width, wall.length),
            height: kind == .door ? min(2.1, wall.height) : 1.2, sillHeight: kind == .door ? 0 : 0.9,
            isOpen: nil, style: kind == .door ? .swingDoor : .slidingWindow)
    }

    /// 新柱子：离墙 60cm 以内就贴到墙的室内一侧，方向和墙一致；否则是独立柱，方向和整个空间的主方向一致
    private func newColumn(at p: Vec2) -> FloorPlanData.Column {
        let size = 0.4
        let height = plan.rooms.first { Geo.pointInPolygon(p, $0.floorPolygon) }?.height ?? plan.maxHeight
        let id = "C\(UUID().uuidString.prefix(4))"
        if let wall = plan.walls.min(by: { Geo.distance(p, segment: $0.start, $0.end) < Geo.distance(p, segment: $1.start, $1.end) }),
           Geo.distance(p, segment: wall.start, wall.end) < 0.6 {
            let t = min(max((p - wall.start).dot(wall.direction), size / 2), max(wall.length - size / 2, size / 2))
            let foot = wall.start + wall.direction * t
            let center = foot - wall.outward * (size / 2)
            return FloorPlanData.Column(id: id, kind: .pilaster, center: center, width: size, depth: size,
                                        yaw: atan2(wall.direction.y, wall.direction.x), height: height, wallIds: [], source: "manual")
        }
        return FloorPlanData.Column(id: id, kind: .freestanding, center: p, width: size, depth: size,
                                    yaw: WallCleanup.dominantAngle(plan.walls), height: height, wallIds: [], source: "manual")
    }

    private func saveColumn(_ c: FloorPlanData.Column) {
        if let i = project.plan.columns.firstIndex(where: { $0.id == c.id }) {
            project.plan.columns[i] = c
        } else {
            project.plan.columns.append(c)
        }
        persist()
    }

    private func deleteColumn(_ id: String) {
        project.plan.columns.removeAll { $0.id == id }
        persist()
    }

    // MARK: - 墙体整理

    private var cleanupBackupURL: URL {
        store.directory(for: project.id).appendingPathComponent("plan_before_cleanup.json")
    }

    private var hasCleanupBackup: Bool { FileManager.default.fileExists(atPath: cleanupBackupURL.path) }

    private func cleanupWalls() {
        // 只备份第一次整理之前的样子
        if !hasCleanupBackup, let data = try? JSONCoding.encoder.encode(project.plan) {
            try? data.write(to: cleanupBackupURL, options: .atomic)
        }
        let r = WallCleanup.run(&project.plan)
        persist()
        cleanupMessage = String(localized: "拉直 \(r.snapped) 段墙，合并 \(r.merged) 段，去掉 \(r.removed) 段噪点，认出 \(r.pilasters + r.freestanding) 根柱子。")
    }

    private func restoreWalls() {
        guard let data = try? Data(contentsOf: cleanupBackupURL),
              let original = try? JSONCoding.decoder.decode(FloorPlanData.self, from: data) else { return }
        project.plan = original
        try? FileManager.default.removeItem(at: cleanupBackupURL)
        persist()
    }

    private func saveOpening(_ o: FloorPlanData.Opening) {
        if let i = project.plan.openings.firstIndex(where: { $0.id == o.id }) {
            project.plan.openings[i] = o
        } else {
            project.plan.openings.append(o)
        }
        persist()
    }

    private func deleteOpening(_ id: String) {
        project.plan.openings.removeAll { $0.id == id }
        persist()
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
