import SceneKit
import UIKit
import simd

struct ViewOptions: Equatable {
    var showCeiling = false
    var showFixtures = false
    var showDimensions = true
    var selectedRoomId: String?
    var selectedWallId: String?
    var pendingPoint: Vec3?
    var includeAnnotations = true
    var showPhotos = false
}

extension Vec3 {
    var scn: SCNVector3 { SCNVector3(Float(x), Float(y), Float(z)) }
    var simd: simd_float3 { simd_float3(Float(x), Float(y), Float(z)) }
}

/// 往一个「Z 轴朝上」的容器节点里填白模、尺寸标签和标注。
/// 调用方负责把容器节点绕 X 轴转 -90°，变成 SceneKit 的 Y 轴朝上。
enum SceneBuilder {
    static let geometryCategory = 1
    static let labelCategory = 2

    private static let wallColor = UIColor(white: 0.97, alpha: 1)
    private static let selectedColor = UIColor.systemOrange
    private static let dimColor = UIColor.systemBlue
    private static let measureColor = UIColor.systemOrange

    /// 标签放大倍数：房子越大，镜头离得越远，标签要跟着放大才看得清
    private static var labelScale: Float = 1

    static func populate(_ root: SCNNode, plan: FloorPlanData, options: ViewOptions) {
        let b = plan.bounds
        labelScale = Float(max(1, max(b.max.x - b.min.x, b.max.y - b.min.y) / 5))
        let wb = WhiteboxBuilder.build(plan)
        let wallMat = material(wallColor)
        let selMat = material(selectedColor.withAlphaComponent(0.9))

        for box in wb.walls {
            let node = boxNode(box, material: box.ownerId == options.selectedWallId ? selMat : wallMat)
            node.name = "wall:\(box.ownerId)"
            root.addChildNode(node)
        }

        for slab in wb.floors {
            let tint = slab.roomId == options.selectedRoomId
                ? UIColor.systemBlue.withAlphaComponent(0.18).blended(over: UIColor(white: 0.9, alpha: 1))
                : UIColor(white: 0.88, alpha: 1)
            let node = slabNode(slab, material: material(tint), depth: 0.02)
            node.name = "floor:\(slab.roomId)"
            root.addChildNode(node)
        }

        if options.showCeiling {
            for slab in wb.ceilings {
                let node = slabNode(slab, material: material(UIColor(white: 0.95, alpha: 1), transparency: 0.55), depth: 0.02)
                node.name = "ceiling:\(slab.roomId)"
                root.addChildNode(node)
            }
        }

        if options.showFixtures {
            let mat = material(UIColor.systemTeal.withAlphaComponent(0.6), transparency: 0.7)
            for (box, fixture) in zip(wb.fixtures, plan.fixtures) {
                let node = boxNode(box, material: mat)
                node.name = "fixture:\(fixture.id)"
                root.addChildNode(node)
                root.addChildNode(label(fixture.name, at: fixture.center + Vec3(0, 0, fixture.size.z / 2 + 0.12),
                                        color: .systemTeal, fontSize: 10))
            }
        }

        if options.showDimensions {
            addDimensionLabels(root, plan: plan, options: options)
        }

        if options.includeAnnotations && options.showPhotos {
            addSitePhotos(root, plan: plan, roomFilter: options.selectedRoomId)
        }

        if options.includeAnnotations {
            addAnnotations(root, plan: plan)
            if let p = options.pendingPoint {
                let s = SCNNode(geometry: SCNSphere(radius: 0.04))
                s.geometry?.firstMaterial = flatMaterial(measureColor)
                s.position = p.scn
                root.addChildNode(s)
            }
        }
    }

    // MARK: - 尺寸标签

    private static func addDimensionLabels(_ root: SCNNode, plan: FloorPlanData, options: ViewOptions) {
        let roomFilter = options.selectedRoomId

        for room in plan.rooms where room.floorPolygon.count >= 3 {
            let c = Geo.centroid(room.floorPolygon)
            let text = String(localized: "\(room.name) \(Fmt.area(room.area))㎡ · 层高 \(Fmt.mm(room.height))")
            root.addChildNode(label(text, at: Vec3(c.x, c.y, 0.15), color: .label, fontSize: 13))

            // 房间一角的竖向层高标尺
            guard roomFilter == nil || roomFilter == room.id else { continue }
            let corner = room.floorPolygon[0]
            let p = corner + (c - corner).normalized * 0.25
            let ruler = SCNNode(geometry: SCNCylinder(radius: 0.008, height: CGFloat(room.height)))
            ruler.geometry?.firstMaterial = flatMaterial(dimColor)
            ruler.position = Vec3(p.x, p.y, room.height / 2).scn
            ruler.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            ruler.categoryBitMask = labelCategory
            root.addChildNode(ruler)
            for z in [0.0, room.height] {
                let tick = SCNNode(geometry: SCNBox(width: 0.12, height: 0.12, length: 0.008, chamferRadius: 0))
                tick.geometry?.firstMaterial = flatMaterial(dimColor)
                tick.position = Vec3(p.x, p.y, z).scn
                tick.categoryBitMask = labelCategory
                root.addChildNode(tick)
            }
            root.addChildNode(label(String(localized: "高 \(Fmt.mm(room.height))"), at: Vec3(p.x, p.y, room.height / 2), color: dimColor, fontSize: 12))
        }

        for wall in plan.walls {
            let isSelected = wall.id == options.selectedWallId
            let inRoom = roomFilter == nil || wall.roomIds.contains(roomFilter!)
            guard inRoom || isSelected else { continue }
            var text = Fmt.mm(wall.length)
            if let m = wall.measuredLength { text += String(localized: "（实测 \(Fmt.mm(m))）") }
            if let h = plan.differingWallHeight(wall) { text += String(localized: " · 高 \(Fmt.mm(h))") }
            let mid = wall.midpoint
            root.addChildNode(label(text, at: Vec3(mid.x, mid.y, wall.height + 0.15),
                                    color: isSelected ? selectedColor : dimColor, fontSize: 12))
        }

        // 选中房间时，门窗尺寸也显示出来
        guard let roomId = roomFilter else { return }
        for o in plan.openings {
            guard let wall = plan.wall(o.wallId), wall.roomIds.contains(roomId) else { continue }
            let p = wall.start + wall.direction * o.centerOffset - wall.outward * 0.15
            let z = o.sillHeight + o.height / 2
            let text: String
            switch o.kind {
            case .door, .opening: text = "\(L10n.title(o)) \(Fmt.mm(o.width))×\(Fmt.mm(o.height))"
            case .window: text = String(localized: "\(L10n.title(o)) \(Fmt.mm(o.width))×\(Fmt.mm(o.height)) 离地\(Fmt.mm(o.sillHeight))")
            }
            root.addChildNode(label(text, at: Vec3(p.x, p.y, z), color: o.kind == .door ? .systemGreen : .systemBlue, fontSize: 10))
        }
    }

    // MARK: - 标注

    private static func addAnnotations(_ root: SCNNode, plan: FloorPlanData) {
        for ann in plan.annotations {
            switch ann.kind {
            case .note:
                let pin = SCNNode(geometry: SCNSphere(radius: 0.07))
                pin.geometry?.firstMaterial = flatMaterial(.systemBlue)
                pin.position = ann.position.scn
                pin.name = "ann:\(ann.id)"
                root.addChildNode(pin)
                let icon = ann.photos.isEmpty ? "" : " 📷"
                root.addChildNode(label("\(ann.number)\(icon)", at: ann.position + Vec3(0, 0, 0.16), color: .systemBlue, fontSize: 11))

            case .measurement:
                guard let end = ann.endPosition else { continue }
                let a = ann.position.simd, b = end.simd
                let len = simd_distance(a, b)
                guard len > 0.001 else { continue }
                let cyl = SCNNode(geometry: SCNCylinder(radius: 0.01, height: CGFloat(len)))
                cyl.geometry?.firstMaterial = flatMaterial(measureColor)
                cyl.simdPosition = (a + b) / 2
                cyl.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: simd_normalize(b - a))
                cyl.name = "ann:\(ann.id)"
                root.addChildNode(cyl)
                for p in [a, b] {
                    let dot = SCNNode(geometry: SCNSphere(radius: 0.03))
                    dot.geometry?.firstMaterial = flatMaterial(measureColor)
                    dot.simdPosition = p
                    dot.name = "ann:\(ann.id)"
                    root.addChildNode(dot)
                }
                let mid = (ann.position + end) * 0.5
                root.addChildNode(label(String(localized: "测 \(Fmt.mm(ann.distance ?? Double(len)))"), at: mid + Vec3(0, 0, 0.1),
                                        color: measureColor, fontSize: 11))
            }
        }
    }

    // MARK: - 现场照片：拍摄位置 + 朝向

    private static func addSitePhotos(_ root: SCNNode, plan: FloorPlanData, roomFilter: String?) {
        let color = UIColor.systemPurple
        for photo in plan.sitePhotos where roomFilter == nil || photo.roomId == roomFilter {
            let cam = SCNNode(geometry: SCNSphere(radius: 0.05))
            cam.geometry?.firstMaterial = flatMaterial(color)
            cam.position = photo.cameraPosition.scn
            cam.name = "photo:\(photo.id)"
            root.addChildNode(cam)

            // 朝向：从相机位置指向拍摄方向的一根短棒
            let len: Float = 0.35
            let dir = simd_normalize(photo.cameraDirection.simd)
            let stick = SCNNode(geometry: SCNCylinder(radius: 0.012, height: CGFloat(len)))
            stick.geometry?.firstMaterial = flatMaterial(color.withAlphaComponent(0.8))
            stick.simdPosition = photo.cameraPosition.simd + dir * (len / 2)
            stick.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: dir)
            stick.name = "photo:\(photo.id)"
            root.addChildNode(stick)
        }
    }

    // MARK: - 节点工具

    static func boxNode(_ box: WhiteboxBox, material: SCNMaterial) -> SCNNode {
        let geo = SCNBox(width: CGFloat(box.size.x), height: CGFloat(box.size.y), length: CGFloat(box.size.z), chamferRadius: 0)
        geo.materials = [material]
        let node = SCNNode(geometry: geo)
        node.position = box.center.scn
        node.eulerAngles = SCNVector3(0, 0, Float(box.yaw))
        return node
    }

    private static func slabNode(_ slab: WhiteboxSlab, material: SCNMaterial, depth: CGFloat) -> SCNNode {
        let path = UIBezierPath()
        for (i, p) in slab.polygon.enumerated() {
            let pt = CGPoint(x: p.x, y: p.y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.close()
        path.flatness = 0.01
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        let offset = slab.z == 0 ? -Float(depth) / 2 : Float(depth) / 2
        node.position = SCNVector3(0, 0, Float(slab.z) + offset)
        return node
    }

    /// 始终朝向镜头、始终显示在最前面的文字标签
    static func label(_ text: String, at p: Vec3, color: UIColor, fontSize: CGFloat) -> SCNNode {
        let geo = SCNText(string: text, extrusionDepth: 0)
        geo.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        geo.flatness = 0.2
        let textMat = flatMaterial(color)
        textMat.readsFromDepthBuffer = false
        geo.materials = [textMat]

        let textNode = SCNNode(geometry: geo)
        let (lo, hi) = textNode.boundingBox
        let cx = (lo.x + hi.x) / 2, cy = (lo.y + hi.y) / 2
        textNode.pivot = SCNMatrix4MakeTranslation(cx, cy, 0)
        textNode.scale = SCNVector3(0.01 * labelScale, 0.01 * labelScale, 0.01 * labelScale)
        textNode.renderingOrder = 101
        textNode.categoryBitMask = labelCategory

        let plate = SCNPlane(width: CGFloat(hi.x - lo.x) + 6, height: CGFloat(hi.y - lo.y) + 4)
        plate.cornerRadius = plate.height / 4
        let plateMat = flatMaterial(UIColor.systemBackground.withAlphaComponent(0.85))
        plateMat.readsFromDepthBuffer = false
        plate.materials = [plateMat]
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(cx, cy, -0.1)
        plateNode.renderingOrder = 100
        plateNode.categoryBitMask = labelCategory
        textNode.addChildNode(plateNode)

        let holder = SCNNode()
        holder.position = p.scn
        holder.constraints = [SCNBillboardConstraint()]
        holder.categoryBitMask = labelCategory
        holder.addChildNode(textNode)
        return holder
    }

    static func material(_ color: UIColor, transparency: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .lambert
        m.transparency = transparency
        m.isDoubleSided = true
        return m
    }

    private static func flatMaterial(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .constant
        m.isDoubleSided = true
        return m
    }
}

private extension UIColor {
    func blended(over base: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        base.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * a1 + r2 * (1 - a1), green: g1 * a1 + g2 * (1 - a1), blue: b1 * a1 + b2 * (1 - a1), alpha: 1)
    }
}
