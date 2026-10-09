import Metal
import SceneKit
import UIKit

/// 给 AI 生图用的素材：在现场照片的位置和角度渲染「空房间白模图」和「深度图」（近白远黑）。
/// 白模图让 AI 看到准确的空间和透视，深度图可以给支持结构控制的生图工具（如 ControlNet）锁住空间。
enum AIImageRenderer {
    struct Shot {
        var id: String
        var photo: String?
        var position: Vec3
        var direction: Vec3
        var up: Vec3
        var verticalFov: Double
    }

    static let imageSize = CGSize(width: 1080, height: 1440)

    /// 选取视角：手动拍的照片优先，其余从自动拍的里均匀挑；没有照片就每个房间从一个角往里看
    static func shots(for plan: FloorPlanData, maxCount: Int = 12) -> [Shot] {
        let manual = plan.sitePhotos.filter { !$0.isAuto }
        let auto = plan.sitePhotos.filter { $0.isAuto }
        var picked = Array(manual.prefix(maxCount))
        if picked.count < maxCount, !auto.isEmpty {
            let need = maxCount - picked.count
            let step = max(Double(auto.count) / Double(need), 1)
            var i = 0.0
            while Int(i) < auto.count, picked.count < maxCount {
                picked.append(auto[Int(i)])
                i += step
            }
        }
        var shots = picked.map {
            Shot(id: $0.id, photo: $0.path, position: $0.cameraPosition, direction: $0.cameraDirection,
                 up: $0.cameraUp, verticalFov: $0.verticalFov)
        }
        if shots.isEmpty {
            for r in plan.rooms where r.floorPolygon.count >= 3 {
                let c = Geo.centroid(r.floorPolygon)
                guard let far = r.floorPolygon.max(by: { ($0 - c).length < ($1 - c).length }) else { continue }
                let eye = c + (far - c) * 0.85
                let flat = (c - eye).normalized
                let dir = Vec3(flat.x, flat.y, -0.12)
                let len = dir.length
                shots.append(Shot(id: r.id, photo: nil, position: Vec3(eye.x, eye.y, 1.5),
                                  direction: dir * (1 / len), up: Vec3(0, 0, 1), verticalFov: 70))
            }
        }
        return shots
    }

    static func render(_ plan: FloorPlanData, shot: Shot, depth: Bool) -> UIImage? {
        if !Thread.isMainThread {
            var image: UIImage?
            DispatchQueue.main.sync { image = render(plan, shot: shot, depth: depth) }
            return image
        }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let scene = SCNScene()
        let container = SCNNode()
        container.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(container)
        SceneBuilder.populate(container, plan: plan,
                              options: ViewOptions(showCeiling: true, showDimensions: false, includeAnnotations: false,
                                                   ceilingOpacity: 1))

        if depth {
            // 室内视角能看到的距离一般在几米以内，固定 0.3–6m 的范围，近处和远处才拉得开
            applyDepthMaterial(container, near: 0.3, far: 6)
            scene.background.contents = UIColor.black
        } else {
            scene.background.contents = UIColor(white: 0.82, alpha: 1)
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 650
            scene.rootNode.addChildNode(ambient)
        }

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = CGFloat(shot.verticalFov)
        cam.camera?.projectionDirection = .vertical
        cam.camera?.zNear = 0.05
        cam.camera?.zFar = 200
        let eye = container.simdConvertPosition(shot.position.simd, to: nil)
        let dir = container.simdConvertVector(shot.direction.simd, to: nil)
        let up = container.simdConvertVector(shot.up.simd, to: nil)
        cam.simdPosition = eye
        cam.simdLook(at: eye + simd_normalize(dir), up: simd_normalize(up), localFront: simd_float3(0, 0, -1))
        scene.rootNode.addChildNode(cam)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cam
        renderer.autoenablesDefaultLighting = !depth
        return renderer.snapshot(atTime: 0, with: imageSize, antialiasingMode: .multisampling4X)
    }

    /// 所有几何体换成「按到镜头的距离着色」的材质：近处白、远处黑
    private static func applyDepthMaterial(_ root: SCNNode, near: Double, far: Double) {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.shaderModifiers = [.fragment: """
        #pragma arguments
        float nearDepth;
        float farDepth;
        #pragma body
        float d = length(_surface.position);
        float v = clamp(1.0 - (d - nearDepth) / (farDepth - nearDepth), 0.0, 1.0);
        _output.color = float4(v, v, v, 1.0);
        """]
        m.setValue(NSNumber(value: near), forKey: "nearDepth")
        m.setValue(NSNumber(value: far), forKey: "farDepth")
        root.enumerateHierarchy { node, _ in
            node.geometry?.materials = [m]
        }
    }
}
