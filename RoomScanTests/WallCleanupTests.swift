import XCTest
@testable import RoomScan

final class WallCleanupTests: XCTestCase {
    private func wall(_ id: String, _ a: Vec2, _ b: Vec2, h: Double = 2.7) -> FloorPlanData.Wall {
        .init(id: id, roomIds: ["R1"], start: a, end: b, length: 0, height: h, thickness: 0.12,
              outward: Vec2(0, 0), measuredLength: nil, isCurved: false)
    }

    private func plan(walls: [FloorPlanData.Wall], openings: [FloorPlanData.Opening] = []) -> FloorPlanData {
        var p = FloorPlanData(schemaVersion: 1, meta: .make(projectName: "test"),
                              rooms: [.init(id: "R1", name: "R", category: "x",
                                            floorPolygon: [Vec2(0, 0), Vec2(6, 0), Vec2(6, 4), Vec2(0, 4)], height: 2.7, area: 0)],
                              walls: walls, openings: openings, fixtures: [], annotations: [])
        p.recomputeDerived()
        return p
    }

    private func angleOK(_ w: FloorPlanData.Wall) -> Bool {
        let a = atan2(w.end.y - w.start.y, w.end.x - w.start.x)
        let r = a.truncatingRemainder(dividingBy: .pi / 2)
        return min(abs(r), abs(abs(r) - .pi / 2)) < 0.001
    }

    /// 6×4 房间：南墙拆成两段（要合并）、东墙中间 1cm 噪点（要删）、北墙歪 3°（要拉直）、中间一根独立柱
    func testStraightenMergeNoiseAndFreestanding() {
        let tilt = tan(3.0 * .pi / 180) * 6
        var p = plan(walls: [
            wall("S1", Vec2(0, 0), Vec2(2.5, 0)), wall("S2", Vec2(2.5, 0), Vec2(6, 0)),
            wall("E1", Vec2(6, 0), Vec2(6, 2)), wall("EN", Vec2(6, 2), Vec2(6.005, 2.008)), wall("E2", Vec2(6.005, 2.008), Vec2(6, 4)),
            wall("N", Vec2(6, 4), Vec2(0, 4 + tilt)), wall("W", Vec2(0, 4 + tilt), Vec2(0, 0)),
            wall("C1", Vec2(3, 2), Vec2(3.5, 2)), wall("C2", Vec2(3.5, 2), Vec2(3.5, 2.5)),
            wall("C3", Vec2(3.5, 2.5), Vec2(3, 2.5)), wall("C4", Vec2(3, 2.5), Vec2(3, 2)),
        ], openings: [.init(id: "D1", kind: .door, wallId: "S2", centerOffset: 1.0, width: 0.9, height: 2.1, sillHeight: 0, isOpen: nil)])

        let r = WallCleanup.run(&p)
        XCTAssertEqual(r.removed, 1)
        XCTAssertEqual(r.merged, 2)
        XCTAssertEqual(r.freestanding, 1)
        XCTAssertEqual(r.pilasters, 0, "独立柱不能再被算成贴墙柱")
        XCTAssertEqual(p.walls.count, 8)
        XCTAssertTrue(p.walls.allSatisfy(angleOK), "所有墙都应该拉直")
        // 门还在原来的位置（x = 3.5）
        let d = p.openings[0]
        let w = p.wall(d.wallId)!
        XCTAssertEqual((w.start + w.direction * d.centerOffset).x, 3.5, accuracy: 0.01)
    }

    /// 墙上凸出一根 600×300 的柱子，其中一面扫歪了 20°
    func testPilasterWithCrookedSide() {
        let skew = tan(20.0 * .pi / 180) * 0.3
        var p = plan(walls: [
            wall("A", Vec2(0, 0), Vec2(2, 0)),
            wall("S1", Vec2(2, 0), Vec2(2, 0.3)),
            wall("F", Vec2(2, 0.3), Vec2(2.6, 0.3)),
            wall("S2", Vec2(2.6, 0.3), Vec2(2.6 + skew, 0)),
            wall("B", Vec2(2.6 + skew, 0), Vec2(6, 0)),
            wall("E", Vec2(6, 0), Vec2(6, 4)), wall("N", Vec2(6, 4), Vec2(0, 4)), wall("W", Vec2(0, 4), Vec2(0, 0)),
        ])
        let r = WallCleanup.run(&p)
        XCTAssertEqual(r.pilasters, 1)
        XCTAssertEqual(r.removed, 0, "柱子的面不能当成噪点删掉")
        XCTAssertTrue(p.walls.allSatisfy(angleOK))
        let c = p.columns[0]
        XCTAssertEqual(c.kind, .pilaster)
        // 扫歪的那一面按中点拉直，误差减半：20° × 30cm 的歪斜，宽度大约偏 5cm
        XCTAssertEqual(c.width, 0.6, accuracy: 0.06)
        XCTAssertEqual(c.depth, 0.3, accuracy: 0.03)
        XCTAssertEqual(Set(c.wallIds), ["S1", "F", "S2"])
    }

    func testCleanupIsIdempotent() {
        var p = SampleData.plan()
        WallCleanup.run(&p)
        let once = p
        let r = WallCleanup.run(&p)
        XCTAssertEqual(r.snapped, 0)
        XCTAssertEqual(p.walls.count, once.walls.count)
        for (a, b) in zip(p.walls, once.walls) {
            XCTAssertLessThan((a.start - b.start).length, 1e-9)
            XCTAssertLessThan((a.end - b.end).length, 1e-9)
        }
    }

    func testManualColumnBecomesGeometry() {
        let p = SampleData.plan()
        let wb = WhiteboxBuilder.build(p)
        XCTAssertEqual(wb.columns.count, p.columns.filter { $0.wallIds.isEmpty }.count)
        XCTAssertFalse(wb.columns.isEmpty)
    }

    func testGLBIsValid() throws {
        let p = SampleData.plan()
        let glb = GLBExporter.export(p, whitebox: WhiteboxBuilder.build(p))
        XCTAssertEqual(String(data: glb.prefix(4), encoding: .ascii), "glTF")
        XCTAssertEqual(glb.count % 4, 0)
        let jsonLength = Int(glb.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) })
        let json = try JSONSerialization.jsonObject(with: glb.subdata(in: 20..<(20 + jsonLength))) as? [String: Any]
        XCTAssertNotNil(json?["meshes"])
    }
}
