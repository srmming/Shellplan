import Foundation
import RoomPlan
import simd

/// 扫描时拍的照片，位姿还在 ARKit 坐标系里，生成白模时再转换
struct PendingPhoto {
    var relativePath: String
    var cameraTransform: simd_float4x4
    var target: simd_float3?
    /// 竖拍画面的垂直视角（度）
    var verticalFov: Double
    var isAuto: Bool
    var createdAt: Date
}

/// RoomPlan 的 CapturedStructure / CapturedRoom → FloorPlanData。
/// ARKit 是 Y 轴朝上，这里统一转换成 Z 轴朝上：(x, y, z)ᴬᴿ → (x, -z, y - 地面高度)
enum RoomPlanAdapter {
    static let defaultWallThickness = 0.12

    static func makePlan(structure: CapturedStructure, scannedRooms: [CapturedRoom], roomNames: [String],
                         photos: [PendingPhoto], projectName: String) -> FloorPlanData {
        let rooms = structure.rooms.count == scannedRooms.count ? structure.rooms : scannedRooms
        return make(walls: structure.walls, doors: structure.doors, windows: structure.windows,
                    openings: structure.openings, objects: structure.objects, rooms: rooms,
                    roomNames: roomNames, photos: photos, projectName: projectName)
    }

    static func makePlan(room: CapturedRoom, roomName: String, photos: [PendingPhoto], projectName: String) -> FloorPlanData {
        make(walls: room.walls, doors: room.doors, windows: room.windows, openings: room.openings,
             objects: room.objects, rooms: [room], roomNames: [roomName], photos: photos, projectName: projectName)
    }

    // MARK: - 房间命名

    static func suggestName(for room: CapturedRoom, existing: [String]) -> String {
        let keys = Set(room.objects.compactMap { fixtureInfo($0.category)?.key })
        let base: String
        if keys.contains("toilet") || keys.contains("bathtub") {
            base = RoomName.bathroom
        } else if keys.contains("stove") || keys.contains("oven") {
            base = RoomName.kitchen
        } else if let label = room.sections.first?.label {
            switch label {
            case .livingRoom: base = RoomName.living
            case .bedroom: base = existing.contains(RoomName.masterBedroom) ? RoomName.secondBedroom : RoomName.masterBedroom
            case .bathroom: base = RoomName.bathroom
            case .kitchen: base = RoomName.kitchen
            case .diningRoom: base = RoomName.dining
            default: return RoomName.generic(existing.count + 1)
            }
        } else {
            return RoomName.generic(existing.count + 1)
        }
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    // MARK: - 转换

    private static func make(walls: [CapturedRoom.Surface], doors: [CapturedRoom.Surface], windows: [CapturedRoom.Surface],
                             openings: [CapturedRoom.Surface], objects: [CapturedRoom.Object], rooms: [CapturedRoom],
                             roomNames: [String], photos: [PendingPhoto], projectName: String) -> FloorPlanData {
        let floorY = walls.map { $0.transform.columns.3.y - $0.dimensions.y / 2 }.min() ?? 0

        func conv(_ p: simd_float3) -> Vec3 { Vec3(Double(p.x), Double(-p.z), Double(p.y - floorY)) }
        func position(_ t: simd_float4x4) -> simd_float3 { simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z) }
        func segment(_ s: CapturedRoom.Surface) -> (Vec2, Vec2) {
            let c = position(s.transform)
            let d = simd_float3(s.transform.columns.0.x, s.transform.columns.0.y, s.transform.columns.0.z)
            let half = s.dimensions.x / 2
            return (conv(c - d * half).xy, conv(c + d * half).xy)
        }

        // 房间
        var planRooms: [FloorPlanData.Room] = []
        for (i, room) in rooms.enumerated() {
            var poly: [Vec2] = []
            if let floor = room.floors.first, floor.polygonCorners.count >= 3 {
                poly = floor.polygonCorners.map { c in
                    let w = floor.transform * simd_float4(c, 1)
                    return conv(simd_float3(w.x, w.y, w.z)).xy
                }
            }
            if poly.count < 3 { poly = Geo.polygonFromSegments(room.walls.map(segment)) }
            let category = room.sections.first.map { categoryKey($0.label) } ?? "unidentified"
            planRooms.append(FloorPlanData.Room(
                id: "R\(i + 1)",
                name: i < roomNames.count ? roomNames[i] : RoomName.generic(i + 1),
                category: category,
                floorPolygon: poly,
                height: room.walls.map { Double($0.dimensions.y) }.max() ?? 2.7,
                area: 0
            ))
        }

        // 墙
        var planWalls: [FloorPlanData.Wall] = []
        var wallIdMap: [UUID: String] = [:]
        for (i, w) in walls.enumerated() {
            let (a, b) = segment(w)
            let id = String(format: "W%02d", i + 1)
            wallIdMap[w.identifier] = id
            planWalls.append(FloorPlanData.Wall(
                id: id, roomIds: roomsNear((a + b) * 0.5, planRooms), start: a, end: b, length: 0,
                height: Double(w.dimensions.y), thickness: defaultWallThickness, outward: Vec2(0, 0),
                measuredLength: nil, isCurved: w.curve != nil
            ))
        }

        // 门窗洞口
        var planOpenings: [FloorPlanData.Opening] = []
        func addOpenings(_ list: [CapturedRoom.Surface], kind: FloorPlanData.OpeningKind, prefix: String) {
            for (i, s) in list.enumerated() {
                let center = conv(position(s.transform))
                var wallIndex: Int?
                if let pid = s.parentIdentifier, let wid = wallIdMap[pid] {
                    wallIndex = planWalls.firstIndex { $0.id == wid }
                }
                if wallIndex == nil {
                    wallIndex = planWalls.indices.min {
                        Geo.distance(center.xy, segment: planWalls[$0].start, planWalls[$0].end)
                            < Geo.distance(center.xy, segment: planWalls[$1].start, planWalls[$1].end)
                    }
                }
                guard let wi = wallIndex else { continue }
                let wall = planWalls[wi]
                let h = Double(s.dimensions.y)
                let bottom = max(0, center.z - h / 2)
                var isOpen: Bool?
                if case .door(let open) = s.category { isOpen = open }
                planOpenings.append(FloorPlanData.Opening(
                    id: "\(prefix)\(i + 1)", kind: kind, wallId: wall.id,
                    centerOffset: (center.xy - wall.start).dot(wall.direction),
                    width: Double(s.dimensions.x),
                    height: kind == .door ? bottom + h : h,
                    sillHeight: kind == .door ? 0 : bottom,
                    isOpen: isOpen
                ))
            }
        }
        addOpenings(doors, kind: .door, prefix: "D")
        addOpenings(windows, kind: .window, prefix: "WIN")
        addOpenings(openings, kind: .opening, prefix: "O")

        // 照片：全部进 sitePhotos（带相机位姿）；手动拍的另外生成一条备注图钉
        // ARKit 相机看向 -Z；竖拍时画面的「上」是相机的 -X
        func dirVec(_ v: simd_float4) -> Vec3 { Vec3(Double(v.x), Double(-v.z), Double(v.y)) }
        var annotations: [FloorPlanData.Annotation] = []
        var sitePhotos: [FloorPlanData.SitePhoto] = []
        for (i, ph) in photos.enumerated() {
            let t = ph.cameraTransform
            let camPos = conv(position(t))
            let dir = dirVec(-t.columns.2)
            let up = dirVec(-t.columns.0)
            let hit = ph.target.map(conv)
            let target = hit ?? camPos + dir * 1.5

            let nearestWall = planWalls.min {
                Geo.distance(target.xy, segment: $0.start, $0.end) < Geo.distance(target.xy, segment: $1.start, $1.end)
            }
            let wallId = nearestWall.flatMap { Geo.distance(target.xy, segment: $0.start, $0.end) < 0.4 ? $0.id : nil }
            let roomId = planRooms.first { Geo.pointInPolygon(camPos.xy, $0.floorPolygon) }?.id
                ?? planRooms.first { Geo.pointInPolygon(target.xy, $0.floorPolygon) }?.id

            sitePhotos.append(FloorPlanData.SitePhoto(
                id: "S\(i + 1)", path: ph.relativePath, roomId: roomId, wallId: wallId,
                cameraPosition: camPos, cameraDirection: dir, cameraUp: up, verticalFov: ph.verticalFov,
                target: hit, isAuto: ph.isAuto, createdAt: ph.createdAt
            ))
            if !ph.isAuto {
                let n = annotations.count + 1
                annotations.append(FloorPlanData.Annotation(
                    id: "P\(n)", number: n, kind: .note, text: String(localized: "扫描时拍的照片"),
                    position: target, endPosition: nil, distance: nil, photos: [ph.relativePath],
                    cameraPosition: camPos, cameraDirection: dir, createdAt: ph.createdAt
                ))
            }
        }

        // 家具和设施一律不要（识别容易出错，也不是白模需要的），只留墙、门窗和柱子
        var plan = FloorPlanData(schemaVersion: 1, meta: .make(projectName: projectName), rooms: planRooms,
                                 walls: planWalls, openings: planOpenings, fixtures: [], annotations: annotations,
                                 sitePhotos: sitePhotos)
        plan.recomputeDerived()
        WallCleanup.run(&plan)
        return plan
    }

    /// 墙中点离哪些房间的轮廓足够近，就属于哪些房间
    private static func roomsNear(_ p: Vec2, _ rooms: [FloorPlanData.Room]) -> [String] {
        let scored = rooms.map { ($0.id, Geo.distanceToEdges(p, polygon: $0.floorPolygon)) }.sorted { $0.1 < $1.1 }
        let near = scored.filter { $0.1 < 0.35 }.map(\.0)
        if !near.isEmpty { return near }
        if let best = scored.first, best.1 < 1.5 { return [best.0] }
        return []
    }

    private static func categoryKey(_ label: CapturedRoom.Section.Label) -> String {
        switch label {
        case .livingRoom: return "livingRoom"
        case .bedroom: return "bedroom"
        case .bathroom: return "bathroom"
        case .kitchen: return "kitchen"
        case .diningRoom: return "diningRoom"
        default: return "unidentified"
        }
    }

    static func fixtureInfo(_ c: CapturedRoom.Object.Category) -> (key: String, name: String)? {
        switch c {
        case .toilet: return ("toilet", FixtureName.toilet)
        case .sink: return ("sink", FixtureName.sink)
        case .bathtub: return ("bathtub", String(localized: "浴缸"))
        case .stove: return ("stove", String(localized: "灶台"))
        case .oven: return ("oven", String(localized: "烤箱"))
        case .refrigerator: return ("refrigerator", String(localized: "冰箱"))
        case .washerDryer: return ("washerDryer", String(localized: "洗衣机/烘干机"))
        case .dishwasher: return ("dishwasher", String(localized: "洗碗机"))
        case .fireplace: return ("fireplace", String(localized: "壁炉"))
        case .stairs: return ("stairs", String(localized: "楼梯"))
        default: return nil
        }
    }
}
