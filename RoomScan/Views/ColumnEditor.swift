import SwiftUI

/// 编辑柱子：手动加的柱子可以改尺寸、挪位置、转方向；自动识别的贴墙柱尺寸由墙决定，只能确认或取消标记
struct ColumnEditor: View {
    @State var column: FloorPlanData.Column
    let isNew: Bool
    var onSave: (FloorPlanData.Column) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(column: FloorPlanData.Column, isNew: Bool,
         onSave: @escaping (FloorPlanData.Column) -> Void, onDelete: @escaping () -> Void) {
        _column = State(initialValue: column)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var editable: Bool { column.wallIds.isEmpty }

    private func mm(_ keyPath: WritableKeyPath<FloorPlanData.Column, Double>) -> Binding<Int> {
        Binding(
            get: { Int((column[keyPath: keyPath] * 1000).rounded()) },
            set: { column[keyPath: keyPath] = Double(max($0, 50)) / 1000 }
        )
    }

    /// 沿柱子自身的宽（u）、深（v）方向挪动
    private func move(u: Double, v: Double) {
        let du = Vec2(cos(column.yaw), sin(column.yaw)), dv = du.perpendicular
        column.center = column.center + du * u + dv * v
    }

    var body: some View {
        NavigationStack {
            Form {
                if editable {
                    Section {
                        Picker("类型", selection: $column.kind) {
                            Text("贴墙柱").tag(FloorPlanData.ColumnKind.pilaster)
                            Text("独立柱").tag(FloorPlanData.ColumnKind.freestanding)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("尺寸") {
                        numberRow("宽", value: mm(\.width))
                        numberRow("深", value: mm(\.depth))
                        numberRow("高", value: mm(\.height))
                        Button("转 90°", systemImage: "rotate.right") {
                            var c = column
                            c.yaw += .pi / 2
                            (c.width, c.depth) = (c.depth, c.width)
                            column = c
                        }
                    }
                    Section {
                        HStack {
                            Spacer()
                            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                                GridRow {
                                    Color.clear.frame(width: 44, height: 1)
                                    nudge("chevron.up") { move(u: 0, v: 0.05) }
                                    Color.clear.frame(width: 44, height: 1)
                                }
                                GridRow {
                                    nudge("chevron.left") { move(u: -0.05, v: 0) }
                                    Text("5 cm").font(.caption).foregroundStyle(.secondary)
                                    nudge("chevron.right") { move(u: 0.05, v: 0) }
                                }
                                GridRow {
                                    Color.clear.frame(width: 44, height: 1)
                                    nudge("chevron.down") { move(u: 0, v: -0.05) }
                                    Color.clear.frame(width: 44, height: 1)
                                }
                            }
                            Spacer()
                        }
                    } header: {
                        Text("位置")
                    } footer: {
                        Text("在平面图上看结果。方向按柱子自己的宽和深。")
                    }
                } else {
                    Section {
                        LabeledContent("尺寸", value: "\(Fmt.mm(column.width)) × \(Fmt.mm(column.depth)) mm")
                        LabeledContent("组成的墙", value: column.wallIds.joined(separator: "、"))
                    } footer: {
                        Text("这根柱子是根据扫描的墙自动认出来的，尺寸跟着墙走。如果它其实不是柱子（比如是墙上的凹凸），可以取消标记，墙不会被删除。")
                    }
                }

                if !isNew {
                    Section {
                        Button(editable ? String(localized: "删除这根柱子") : String(localized: "这不是柱子，取消标记"),
                               role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "添加柱子") : L10n.column(column))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(column)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(editable ? String(localized: "删除这根柱子？") : String(localized: "取消柱子标记？"),
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(editable ? String(localized: "删除") : String(localized: "取消标记"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func nudge(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 44, height: 32)
        }
        .buttonStyle(.bordered)
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
