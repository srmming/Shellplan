import ARKit
import CoreImage
import Foundation
import RoomPlan
import UIKit

/// 多房间扫描流程：扫一个房间 → 命名 → 扫下一个（沿用同一个 ARSession，房间自动对齐）→ 合并成全屋
final class ScanController: NSObject, ObservableObject, RoomCaptureViewDelegate {
    enum Phase: Equatable {
        case idle, scanning, processing, naming, betweenRooms, building, done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var roomNames: [String] = []
    @Published private(set) var suggestedName = "客厅"
    @Published private(set) var photoCount = 0
    @Published private(set) var autoPhotoCount = 0
    @Published var autoPhotoEnabled = true
    private(set) var output: ScanOutput?

    let captureView: RoomCaptureView
    private var capturedRooms: [CapturedRoom] = []
    private var photos: [PendingPhoto] = []
    private let workDir: URL
    private let ciContext = CIContext()
    private let photoQueue = DispatchQueue(label: "roomscan.photo", qos: .utility)

    // 自动拍照：手机拿稳、并且换了位置或角度时才拍
    private static let autoInterval: TimeInterval = 0.4
    private static let maxAutoPerRoom = 30
    private var autoTimer: Timer?
    private var lastShotTransform: simd_float4x4?
    private var previousTickTransform: simd_float4x4?
    private var roomAutoCount = 0

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir.appendingPathComponent("photos"), withIntermediateDirectories: true)
        super.init()
        captureView.delegate = self
    }

    // RoomCaptureViewDelegate 要求 NSCoding，这里不需要归档
    required init?(coder: NSCoder) { return nil }
    func encode(with coder: NSCoder) {}

    var currentRoomNumber: Int { capturedRooms.count + 1 }

    // MARK: - 流程控制

    func start() {
        guard phase == .idle else { return }
        run()
    }

    func finishRoom() {
        guard phase == .scanning else { return }
        phase = .processing
        stopAutoTimer()
        captureView.captureSession.stop(pauseARSession: false)
    }

    func confirmName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        roomNames.append(trimmed.isEmpty ? "房间\(roomNames.count + 1)" : trimmed)
        phase = .betweenRooms
    }

    func rescanLastRoom() {
        if !capturedRooms.isEmpty { capturedRooms.removeLast() }
        run()
    }

    func nextRoom() { run() }

    func retry() { run() }

    func finishAll(projectName: String) {
        guard !capturedRooms.isEmpty else { return }
        phase = .building
        stopAutoTimer()
        captureView.captureSession.arSession.pause()
        let rooms = capturedRooms, names = roomNames, photos = self.photos, workDir = self.workDir
        let queue = photoQueue

        Task {
            // 等后台还没写完的照片落盘
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in queue.async { c.resume() } }
            let original = workDir.appendingPathComponent("roomplan_original.usdz")
            var plan: FloorPlanData?
            var failure: String?
            do {
                let structure = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: rooms)
                plan = RoomPlanAdapter.makePlan(structure: structure, scannedRooms: rooms, roomNames: names,
                                                photos: photos, projectName: projectName)
                try? structure.export(to: original, exportOptions: .parametric)
            } catch {
                if rooms.count == 1, let room = rooms.first {
                    plan = RoomPlanAdapter.makePlan(room: room, roomName: names.first ?? "房间1",
                                                    photos: photos, projectName: projectName)
                    try? room.export(to: original, exportOptions: .parametric)
                } else {
                    failure = "拼合全屋失败：\(error.localizedDescription)"
                }
            }
            let result = plan, message = failure
            await MainActor.run {
                if let result {
                    self.output = ScanOutput(plan: result, workDir: workDir)
                    self.phase = .done
                } else {
                    self.phase = .failed(message ?? "拼合全屋失败")
                }
            }
        }
    }

    func shutdown() {
        stopAutoTimer()
        captureView.captureSession.stop()
        captureView.captureSession.arSession.pause()
    }

    private func run() {
        phase = .scanning
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        roomAutoCount = 0
        lastShotTransform = nil
        previousTickTransform = nil
        stopAutoTimer()
        autoTimer = Timer.scheduledTimer(withTimeInterval: Self.autoInterval, repeats: true) { [weak self] _ in
            self?.autoTick()
        }
    }

    private func stopAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    // MARK: - 拍照（带相机位姿，落到模型里对应的位置）

    /// 手动拍：「这里拍照」按钮，会在模型里生成一个备注图钉
    func capturePhoto() {
        guard let frame = captureView.captureSession.arSession.currentFrame else { return }
        capture(frame, isAuto: false)
        photoCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func autoTick() {
        guard autoPhotoEnabled, phase == .scanning, roomAutoCount < Self.maxAutoPerRoom,
              let frame = captureView.captureSession.arSession.currentFrame,
              case .normal = frame.camera.trackingState else {
            previousTickTransform = nil
            return
        }
        let t = frame.camera.transform
        defer { previousTickTransform = t }

        // 手机拿稳了才拍，避免糊片：两次检查之间移动 < 8cm、转动 < 6°
        guard let prev = previousTickTransform,
              Self.distance(prev, t) < 0.08, Self.angle(prev, t) < 6 else { return }
        // 和上一张比，要换了位置（> 70cm）或换了角度（> 30°）才拍，避免重复
        if let last = lastShotTransform, Self.distance(last, t) < 0.7, Self.angle(last, t) < 30 { return }

        capture(frame, isAuto: true)
        lastShotTransform = t
        roomAutoCount += 1
        autoPhotoCount += 1
    }

    private func capture(_ frame: ARFrame, isAuto: Bool) {
        let session = captureView.captureSession.arSession
        var target: simd_float3?
        let query = frame.raycastQuery(from: CGPoint(x: 0.5, y: 0.5), allowing: .estimatedPlane, alignment: .any)
        if let hit = session.raycast(query).first {
            let c = hit.worldTransform.columns.3
            target = simd_float3(c.x, c.y, c.z)
        }

        // 竖拍时，传感器的水平视角就是画面的垂直视角
        let fx = Double(frame.camera.intrinsics[0][0])
        let sensorWidth = Double(frame.camera.imageResolution.width)
        let fov = 2 * atan(sensorWidth / (2 * fx)) * 180 / .pi

        let rel = "photos/\(isAuto ? "AUTO" : "SCAN")_\(UUID().uuidString.prefix(8)).jpg"
        photos.append(PendingPhoto(relativePath: rel, cameraTransform: frame.camera.transform, target: target,
                                   verticalFov: fov, isAuto: isAuto, createdAt: Date()))

        let pixelBuffer = frame.capturedImage
        let url = workDir.appendingPathComponent(rel)
        let ctx = ciContext
        photoQueue.async {
            let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            guard let cg = ctx.createCGImage(image, from: image.extent),
                  let data = UIImage(cgImage: cg).jpegData(compressionQuality: isAuto ? 0.7 : 0.85) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func distance(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        simd_distance(simd_float3(a.columns.3.x, a.columns.3.y, a.columns.3.z),
                      simd_float3(b.columns.3.x, b.columns.3.y, b.columns.3.z))
    }

    /// 两个相机朝向之间的夹角（度）
    private static func angle(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        let fa = simd_normalize(simd_float3(a.columns.2.x, a.columns.2.y, a.columns.2.z))
        let fb = simd_normalize(simd_float3(b.columns.2.x, b.columns.2.y, b.columns.2.z))
        return acos(min(max(simd_dot(fa, fb), -1), 1)) * 180 / .pi
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.phase = .failed("这个房间处理失败：\(error.localizedDescription)")
                return
            }
            self.capturedRooms.append(processedResult)
            self.suggestedName = RoomPlanAdapter.suggestName(for: processedResult, existing: self.roomNames)
            self.phase = .naming
        }
    }
}
