import RoomPlan
import SwiftUI

struct ScanScreen: View {
    let projectName: String
    var onFinish: (ScanOutput) -> Void

    @StateObject private var controller = ScanController()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCancel = false

    var body: some View {
        ZStack {
            RoomCaptureContainer(view: controller.captureView)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                if let tip { tipBubble(tip) }
                Spacer()
                bottomControls
            }
            .padding()

            if controller.phase == .building {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView("正在拼合全屋，生成白模…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.shutdown() }
        .onChange(of: controller.phase) { _, phase in
            if phase == .done, let output = controller.output { onFinish(output) }
        }
        .sheet(isPresented: Binding(get: { controller.phase == .naming }, set: { _ in })) {
            RoomNameSheet(roomNumber: controller.roomNames.count + 1,
                          suggested: controller.suggestedName,
                          onConfirm: controller.confirmName,
                          onRescan: controller.rescanLastRoom)
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .alert("扫描出错", isPresented: Binding(get: { failureMessage != nil }, set: { _ in })) {
            Button("重新扫这个房间") { controller.retry() }
            Button("退出", role: .cancel) { dismiss() }
        } message: {
            Text(failureMessage ?? "")
        }
        .confirmationDialog("放弃这次扫描？", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续扫描", role: .cancel) {}
        } message: {
            Text("已经扫好的房间不会保存。")
        }
    }

    private var failureMessage: String? {
        if case .failed(let msg) = controller.phase { return msg }
        return nil
    }

    private var tip: String? {
        switch controller.phase {
        case .scanning:
            return controller.autoPhotoEnabled
                ? "慢慢移动手机，对准墙角、门和窗。停一下就会自动拍照"
                : "慢慢移动手机，对准墙角、门和窗"
        case .betweenRooms: return "走到下一个房间门口再点「扫下一个房间」。中途不要退出 App，房间才能自动对齐"
        default: return nil
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .scanning: return "房间 \(controller.currentRoomNumber) · 扫描中"
        case .processing: return "房间 \(controller.currentRoomNumber) · 处理中"
        case .naming, .betweenRooms: return "已完成 \(controller.roomNames.count) 个房间"
        case .building: return "生成白模"
        default: return "准备中"
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                confirmCancel = true
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("退出扫描")
            Spacer()
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .foregroundStyle(.primary)
    }

    private func tipBubble(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var bottomControls: some View {
        switch controller.phase {
        case .scanning:
            HStack(alignment: .bottom) {
                roundButton("camera", "这里拍照", badge: controller.photoCount) { controller.capturePhoto() }
                Spacer()
                Button {
                    controller.finishRoom()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.title.weight(.semibold))
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(.white, lineWidth: 4))
                            .background(.ultraThinMaterial, in: Circle())
                        Text("完成此房间").font(.caption)
                    }
                }
                Spacer()
                roundButton("camera.aperture",
                            controller.autoPhotoEnabled ? "自动拍照 开" : "自动拍照 关",
                            badge: controller.autoPhotoCount) {
                    controller.autoPhotoEnabled.toggle()
                }
                .opacity(controller.autoPhotoEnabled ? 1 : 0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)

        case .processing:
            ProgressView("正在处理这个房间…")
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

        case .betweenRooms:
            VStack(spacing: 12) {
                Text(controller.roomNames.joined(separator: " · "))
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                HStack(spacing: 12) {
                    Button {
                        controller.nextRoom()
                    } label: {
                        Label("扫下一个房间", systemImage: "door.left.hand.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        controller.finishAll(projectName: projectName)
                    } label: {
                        Label("完成，生成全屋", systemImage: "cube")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .controlSize(.large)
            }

        default:
            EmptyView()
        }
    }

    private func roundButton(_ icon: String, _ title: String, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.caption2.bold())
                                .padding(5)
                                .background(.blue, in: Circle())
                                .foregroundStyle(.white)
                        }
                    }
                Text(title).font(.caption)
            }
            .frame(width: 64)
        }
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let view: RoomCaptureView
    func makeUIView(context: Context) -> RoomCaptureView { view }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

struct RoomNameSheet: View {
    let roomNumber: Int
    let suggested: String
    var onConfirm: (String) -> Void
    var onRescan: () -> Void

    @State private var name = ""
    private let presets = ["客厅", "餐厅", "主卧", "次卧", "儿童房", "书房", "厨房", "卫生间", "主卫", "阳台", "玄关", "走廊", "储物间"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("房间名", text: $name)
                        .font(.title3)
                } footer: {
                    Text("名字会写进导出给 AI 的数据里，选准一点 AI 才不会理解错。")
                }
                Section("常用") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 8) {
                        ForEach(presets, id: \.self) { p in
                            Button(p) { name = p }
                                .buttonStyle(.bordered)
                                .tint(name == p ? .accentColor : .secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("第 \(roomNumber) 个房间叫什么？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重扫") { onRescan() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { onConfirm(name) }
                }
            }
        }
        .onAppear { name = suggested }
    }
}
