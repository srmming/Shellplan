import Foundation

/// 示例户型：客厅 + 主卧 + 卫生间。没有 LiDAR 的设备、模拟器和单元测试都用它。
enum SampleData {
    static func plan() -> FloorPlanData {
        typealias W = FloorPlanData.Wall
        func wall(_ id: String, _ rooms: [String], _ a: Vec2, _ b: Vec2) -> W {
            W(id: id, roomIds: rooms, start: a, end: b, length: 0, height: 2.7, thickness: 0.12,
              outward: Vec2(0, 0), measuredLength: nil, isCurved: false)
        }

        let rooms = [
            FloorPlanData.Room(id: "R1", name: RoomName.living, category: "livingRoom",
                               floorPolygon: [Vec2(0, 0), Vec2(4.2, 0), Vec2(4.2, 3.6), Vec2(0, 3.6)], height: 2.7, area: 0),
            FloorPlanData.Room(id: "R2", name: RoomName.masterBedroom, category: "bedroom",
                               floorPolygon: [Vec2(4.2, 0), Vec2(7.4, 0), Vec2(7.4, 3.6), Vec2(4.2, 3.6)], height: 2.7, area: 0),
            FloorPlanData.Room(id: "R3", name: RoomName.bathroom, category: "bathroom",
                               floorPolygon: [Vec2(0, 3.6), Vec2(1.8, 3.6), Vec2(1.8, 5.6), Vec2(0, 5.6)], height: 2.5, area: 0),
        ]

        var walls = [
            wall("W01", ["R1"], Vec2(0, 0), Vec2(4.2, 0)),
            wall("W02", ["R1", "R2"], Vec2(4.2, 0), Vec2(4.2, 3.6)),
            wall("W03", ["R1", "R3"], Vec2(4.2, 3.6), Vec2(0, 3.6)),
            wall("W04", ["R1"], Vec2(0, 3.6), Vec2(0, 0)),
            wall("W05", ["R2"], Vec2(4.2, 0), Vec2(7.4, 0)),
            wall("W06", ["R2"], Vec2(7.4, 0), Vec2(7.4, 3.6)),
            wall("W07", ["R2"], Vec2(7.4, 3.6), Vec2(4.2, 3.6)),
            wall("W08", ["R3"], Vec2(1.8, 3.6), Vec2(1.8, 5.6)),
            wall("W09", ["R3"], Vec2(1.8, 5.6), Vec2(0, 5.6)),
            wall("W10", ["R3"], Vec2(0, 5.6), Vec2(0, 3.6)),
        ]
        for i in walls.indices where walls[i].roomIds.contains("R3") { walls[i].height = 2.5 }
        walls[2].height = 2.7

        let openings = [
            FloorPlanData.Opening(id: "WIN1", kind: .window, wallId: "W01", centerOffset: 2.1, width: 1.4, height: 1.2, sillHeight: 0.9, isOpen: nil, style: .slidingWindow),
            FloorPlanData.Opening(id: "D1", kind: .door, wallId: "W02", centerOffset: 3.0, width: 0.9, height: 2.1, sillHeight: 0, isOpen: true, style: .swingDoor, hinge: .left),
            FloorPlanData.Opening(id: "D2", kind: .door, wallId: "W03", centerOffset: 3.4, width: 0.8, height: 2.1, sillHeight: 0, isOpen: false, style: .slidingDoor),
            FloorPlanData.Opening(id: "D3", kind: .door, wallId: "W04", centerOffset: 1.0, width: 1.0, height: 2.1, sillHeight: 0, isOpen: false, style: .swingDoor, hinge: .right),
            FloorPlanData.Opening(id: "WIN2", kind: .window, wallId: "W05", centerOffset: 1.6, width: 1.6, height: 1.5, sillHeight: 0.6, isOpen: nil, style: .casementWindow),
            FloorPlanData.Opening(id: "WIN3", kind: .window, wallId: "W09", centerOffset: 0.9, width: 0.6, height: 0.6, sillHeight: 1.5, isOpen: nil),
        ]

        // 客厅东墙上一根手动标的贴墙柱
        let columns = [
            FloorPlanData.Column(id: "C1", kind: .pilaster, center: Vec2(3.98, 0.9), width: 0.4, depth: 0.44,
                                 yaw: .pi / 2, height: 2.7, wallIds: [], source: "manual"),
        ]

        let annotations = [
            FloorPlanData.Annotation(id: "A1", number: 1, kind: .note, text: String(localized: "电视墙，留 3 个插座"),
                                     position: Vec3(2.1, 3.55, 0.6), endPosition: nil, distance: nil, photos: [],
                                     cameraPosition: nil, cameraDirection: nil, createdAt: Date(timeIntervalSince1970: 1_760_000_000)),
        ]

        var meta = FloorPlanData.Meta.make(projectName: String(localized: "示例户型"))
        meta.createdAt = Date(timeIntervalSince1970: 1_760_000_000)
        var plan = FloorPlanData(schemaVersion: 1, meta: meta, rooms: rooms, walls: walls, openings: openings,
                                 fixtures: [], annotations: annotations)
        plan.columns = columns
        plan.recomputeDerived()
        return plan
    }
}
