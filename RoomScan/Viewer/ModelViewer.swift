import SceneKit
import SwiftUI

enum ViewerHit {
    case wall(id: String, point: Vec3)
    case annotation(id: String)
    case photo(id: String)
    case column(id: String, point: Vec3)
    case surface(point: Vec3)
    case nothing
}

struct ModelViewer: UIViewRepresentable {
    var plan: FloorPlanData
    var options: ViewOptions
    var onTap: (ViewerHit) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = LayoutAwareSCNView()
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.frameIfNeeded() }
        view.scene = context.coordinator.scene
        // 一开始就挂上自己的相机：否则 SceneKit 可能抢先生成一个默认相机，取景就乱了
        view.pointOfView = context.coordinator.cameraNode
        view.backgroundColor = .secondarySystemBackground
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.render(plan: plan, options: options)
    }

    final class Coordinator: NSObject {
        let scene = SCNScene()
        /// 「Z 轴朝上」的容器，绕 X 轴转 -90° 后对齐 SceneKit 的 Y 轴朝上
        let container = SCNNode()
        let cameraNode = SCNNode()
        weak var view: SCNView?
        var onTap: (ViewerHit) -> Void = { _ in }

        private var lastPlan: FloorPlanData?
        private var lastOptions: ViewOptions?
        private var framed = false

        override init() {
            super.init()
            container.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            scene.rootNode.addChildNode(container)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 500
            scene.rootNode.addChildNode(ambient)

            let camera = SCNCamera()
            camera.zNear = 0.05
            camera.zFar = 200
            camera.fieldOfView = 50
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 10, 10)
            cameraNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(cameraNode)
        }

        func render(plan: FloorPlanData, options: ViewOptions) {
            guard plan != lastPlan || options != lastOptions else { return }
            lastPlan = plan
            lastOptions = options
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            container.childNodes.forEach { $0.removeFromParentNode() }
            SceneBuilder.populate(container, plan: plan, options: options)
            SCNTransaction.commit()
            frameIfNeeded()
        }

        /// 视图有了真实尺寸之后才摆镜头，否则竖屏的取景距离会算错
        func frameIfNeeded() {
            guard !framed, let plan = lastPlan, let view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            framed = true
            frameCamera(plan)
        }

        private func frameCamera(_ plan: FloorPlanData) {
            guard let view else { return }
            let b = plan.bounds
            let center = Vec3((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2, 1.0)
            // 从南边斜上方看过去，再让 SceneKit 按视图比例把所有墙收进画面
            let span = max(b.max.x - b.min.x, b.max.y - b.min.y, 3)
            let camLocal = Vec3(center.x, center.y - span * 0.75, span * 1.45)
            let target = container.convertPosition(center.scn, to: nil)
            cameraNode.position = container.convertPosition(camLocal.scn, to: nil)
            cameraNode.look(at: target)
            view.pointOfView = cameraNode
            view.defaultCameraController.target = target
            let walls = container.childNodes.filter { $0.name?.hasPrefix("wall:") == true }
            if !walls.isEmpty { view.defaultCameraController.frameNodes(walls) }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [
                .categoryBitMask: SceneBuilder.geometryCategory,
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true,
            ])
            guard let hit = hits.first else {
                onTap(.nothing)
                return
            }
            let p = container.convertPosition(hit.worldCoordinates, from: nil)
            let point = Vec3(Double(p.x), Double(p.y), Double(p.z))

            var node: SCNNode? = hit.node
            while let n = node {
                if let name = n.name, let sep = name.firstIndex(of: ":") {
                    let kind = name[..<sep], id = String(name[name.index(after: sep)...])
                    switch kind {
                    case "wall": onTap(.wall(id: id, point: point))
                    case "ann": onTap(.annotation(id: id))
                    case "photo": onTap(.photo(id: id))
                    case "column": onTap(.column(id: id, point: point))
                    default: onTap(.surface(point: point))
                    }
                    return
                }
                node = n.parent
            }
            onTap(.surface(point: point))
        }
    }
}

/// 布局完成时回调，用来在视图有了真实尺寸后再摆镜头
final class LayoutAwareSCNView: SCNView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
