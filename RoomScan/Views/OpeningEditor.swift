import SwiftUI

/// 编辑一个门窗：类型、样式、开向、位置、尺寸；也用来添加和删除
struct OpeningEditor: View {
    let plan: FloorPlanData
    @State var opening: FloorPlanData.Opening
    let isNew: Bool
    var onSave: (FloorPlanData.Opening) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(plan: FloorPlanData, opening: FloorPlanData.Opening, isNew: Bool,
         onSave: @escaping (FloorPlanData.Opening) -> Void, onDelete: @escaping () -> Void) {
        self.plan = plan
        _opening = State(initialValue: opening)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var wall: FloorPlanData.Wall? { plan.wall(opening.wallId) }

    /// 数值以毫米编辑，存的时候换回米
    private func mm(_ keyPath: WritableKeyPath<FloorPlanData.Opening, Double>) -> Binding<Int> {
        Binding(
            get: { Int((opening[keyPath: keyPath] * 1000).rounded()) },
            set: { opening[keyPath: keyPath] = Double(max($0, 0)) / 1000 }
        )
    }

    /// 门窗左边缘到左侧墙角的距离（mm），改它就是左右挪动门窗
    private var leftGap: Binding<Int> {
        Binding(
            get: { Int(((plan.cornerGaps(of: opening)?.left ?? 0) * 1000).rounded()) },
            set: { newValue in
                guard let w = wall else { return }
                let gap = Double(newValue) / 1000
                // 左侧墙角在墙的哪一端，决定往哪个方向算
                let leftIsEnd = w.direction.dot(w.leftDirection) > 0
                opening.centerOffset = leftIsEnd ? w.length - gap - opening.width / 2 : gap + opening.width / 2
                clamp()
            }
        )
    }

    private func nudge(_ deltaMM: Int) {
        leftGap.wrappedValue += deltaMM
    }

    /// 不让门窗跑出墙外、比墙还高
    private func clamp() {
        guard let w = wall else { return }
        opening.width = min(max(opening.width, 0.2), w.length)
        opening.centerOffset = min(max(opening.centerOffset, opening.width / 2), w.length - opening.width / 2)
        if opening.kind != .window { opening.sillHeight = 0 }
        opening.height = min(max(opening.height, 0.2), w.height - opening.sillHeight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $opening.kind) {
                        Text("门").tag(FloorPlanData.OpeningKind.door)
                        Text("窗").tag(FloorPlanData.OpeningKind.window)
                        Text("洞口").tag(FloorPlanData.OpeningKind.opening)
                    }
                    .pickerStyle(.segmented)

                    let styles = FloorPlanData.OpeningStyle.styles(for: opening.kind)
                    if !styles.isEmpty {
                        Picker("样式", selection: $opening.style) {
                            Text("未确认").tag(FloorPlanData.OpeningStyle?.none)
                            ForEach(styles, id: \.self) { style in
                                Text(L10n.style(style)).tag(FloorPlanData.OpeningStyle?.some(style))
                            }
                        }
                    }

                    if opening.kind == .door && (opening.style == nil || opening.style == .swingDoor || opening.style == .foldingDoor)
                        || opening.kind == .window && opening.style == .casementWindow {
                        Picker("门轴 / 合页", selection: Binding(
                            get: { opening.hinge ?? .left },
                            set: { opening.hinge = $0 })) {
                            Text("左边").tag(FloorPlanData.HingeSide.left)
                            Text("右边").tag(FloorPlanData.HingeSide.right)
                        }
                        .pickerStyle(.segmented)
                    }
                    if opening.kind == .door && (opening.style == nil || opening.style == .swingDoor) {
                        Picker("开向", selection: Binding(
                            get: { opening.opensOutward ?? false },
                            set: { opening.opensOutward = $0 })) {
                            Text("往里开").tag(false)
                            Text("往外开").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Text("左右按「站在这个房间里、面朝这面墙」来看。")
                }

                Section("位置") {
                    numberRow("离左侧墙角", value: leftGap)
                    HStack {
                        ForEach([-100, -10, 10, 100], id: \.self) { step in
                            Button(step > 0 ? "+\(step)" : "\(step)") { nudge(step) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let gaps = plan.cornerGaps(of: opening) {
                        LabeledContent("离右侧墙角", value: "\(Fmt.mm(gaps.right)) mm")
                    }
                }

                Section("尺寸") {
                    numberRow("宽", value: mm(\.width))
                    numberRow("高", value: mm(\.height))
                    if opening.kind == .window {
                        numberRow("离地", value: mm(\.sillHeight))
                    }
                }

                if let wall {
                    Section {
                        LabeledContent("所在的墙", value: "\(wall.id) · \(Fmt.mm(wall.length)) × \(Fmt.mm(wall.height)) mm")
                    }
                }

                if !isNew {
                    Section {
                        Button("删除这个门窗", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "添加门窗") : L10n.title(opening))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        clamp()
                        onSave(opening)
                        dismiss()
                    }
                }
            }
            .onChange(of: opening.kind) { _, kind in
                // 换了类型，样式也要换成这个类型下的
                if let style = opening.style, !FloorPlanData.OpeningStyle.styles(for: kind).contains(style) {
                    opening.style = nil
                }
                if kind != .window { opening.sillHeight = 0 }
            }
            .confirmationDialog("删除这个门窗？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func numberRow(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField("", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text("mm").foregroundStyle(.secondary)
            }
        } label: {
            Text(title)
        }
    }
}
