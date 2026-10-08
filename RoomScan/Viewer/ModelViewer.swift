import SceneKit
import SwiftUI

enum ViewerHit {
    case wall(id: String, point: Vec3)
    case annotation(id: String)
    case photo(id: String)
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
            // 竖屏时水平视野窄，镜头要退得更远才能把整套房子放进画面
            let aspect = view.bounds.width / max(view.bounds.height, 1)
            let distance = max(b.max.x - b.min.x, b.max.y - b.min.y, 3) * max(1, 0.62 / aspect)
            let camLocal = Vec3(center.x, center.y - distance * 0.95, distance * 1.15)
            let camWorld = container.convertPosition(camLocal.scn, to: nil)
            let target = container.convertPosition(center.scn, to: nil)

            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera?.zNear = 0.05
            cam.camera?.zFar = 200
            cam.camera?.fieldOfView = 50
            cam.position = camWorld
            cam.look(at: target)
            scene.rootNode.addChildNode(cam)
            view.pointOfView = cam
            view.defaultCameraController.target = target
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
