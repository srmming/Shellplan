import XCTest
@testable import RoomScan

final class WhiteboxTests: XCTestCase {
    private func opening(_ kind: FloorPlanData.OpeningKind, center: Double, width: Double, height: Double, sill: Double) -> FloorPlanData.Opening {
        FloorPlanData.Opening(id: UUID().uuidString, kind: kind, wallId: "W", centerOffset: center,
                              width: width, height: height, sillHeight: sill, isOpen: nil)
    }

    func testSolidWallIsOnePiece() {
        let pieces = WhiteboxBuilder.pieces(length: 4, height: 2.7, openings: [])
        XCTAssertEqual(pieces, [.init(u0: 0, u1: 4, z0: 0, z1: 2.7)])
    }

    func testDoorLeavesHole() {
        let pieces = WhiteboxBuilder.pieces(length: 4, height: 2.7,
                                            openings: [opening(.door, center: 2, width: 0.9, height: 2.1, sill: 0)])
        XCTAssertEqual(pieces.count, 3) // 左、门上方、右
        XCTAssertFalse(pieces.contains { $0.u0 < 2 && $0.u1 > 2 && $0.z0 < 1 }, "门洞位置不应该有墙")
        let volume = pieces.reduce(0) { $0 + ($1.u1 - $1.u0) * ($1.z1 - $1.z0) }
        XCTAssertEqual(volume, 4 * 2.7 - 0.9 * 2.1, accuracy: 1e-9)
    }

    func testWindowHasPiecesBelowAndAbove() {
        let pieces = WhiteboxBuilder.pieces(length: 4, height: 2.7,
                                            openings: [opening(.window, center: 2, width: 1.4, height: 1.2, sill: 0.9)])
        XCTAssertEqual(pieces.count, 4) // 左、窗下、窗上、右
        let volume = pieces.reduce(0) { $0 + ($1.u1 - $1.u0) * ($1.z1 - $1.z0) }
        XCTAssertEqual(volume, 4 * 2.7 - 1.4 * 1.2, accuracy: 1e-9)
    }

    func testSamplePlanDerivedValues() {
        let plan = SampleData.plan()
        XCTAssertEqual(plan.rooms[0].area, 4.2 * 3.6, accuracy: 1e-6)
        XCTAssertEqual(plan.wall("W01")!.length, 4.2, accuracy: 1e-9)
        // 客厅南墙的外侧朝 -y
        XCTAssertEqual(plan.wall("W01")!.outward.y, -1, accuracy: 1e-9)
        XCTAssertEqual(plan.totalArea, 4.2 * 3.6 + 3.2 * 3.6 + 1.8 * 2.0, accuracy: 1e-6)
    }

    func testTriangulateLShape() {
        let l = [Vec2(0, 0), Vec2(3, 0), Vec2(3, 1), Vec2(1, 1), Vec2(1, 3), Vec2(0, 3)]
        let tris = Geo.triangulate(l)
        XCTAssertEqual(tris.count, 4)
        let area = tris.reduce(0) { $0 + Geo.polygonArea($1.map { l[$0] }) }
        XCTAssertEqual(area, Geo.polygonArea(l), accuracy: 1e-9)
    }

    func testJSONRoundTrip() throws {
        let plan = SampleData.plan()
        let data = try JSONCoding.encoder.encode(plan)
        let back = try JSONCoding.decoder.decode(FloorPlanData.self, from: data)
        XCTAssertEqual(plan, back)
    }

    func testOBJIsWellFormed() {
        let plan = SampleData.plan()
        let wb = WhiteboxBuilder.build(plan)
        let (obj, mtl) = OBJExporter.export(plan, whitebox: wb)
        let lines = obj.split(separator: "\n")
        let vertexCount = lines.filter { $0.hasPrefix("v ") }.count
        let expected = (wb.walls.count + wb.fixtures.count) * 8 + (wb.floors + wb.ceilings).reduce(0) { $0 + $1.polygon.count }
        XCTAssertEqual(vertexCount, expected)
        for face in lines where face.hasPrefix("f ") {
            for idx in face.split(separator: " ").dropFirst() {
                let i = Int(idx)!
                XCTAssertTrue(i >= 1 && i <= vertexCount)
            }
        }
        XCTAssertTrue(mtl.contains("newmtl Wall"))
    }

    func testFloorPlanRenders() {
        let plan = SampleData.plan()
        let image = FloorPlanRenderer.image(plan, width: 800)
        XCTAssertEqual(image.size.width, 800)
        XCTAssertNotNil(image.pngData())
        let pdf = FloorPlanRenderer.pdfData(plan)
        XCTAssertEqual(String(data: pdf.prefix(4), encoding: .ascii), "%PDF")
    }

    func testExportPackage() throws {
        let now = Date()
        let project = Project(id: UUID(), name: "测试 户型", createdAt: now, updatedAt: now, plan: SampleData.plan())
        let zip = try ExportPackager.makePackage(project: project, projectDir: FileManager.default.temporaryDirectory)
        XCTAssertEqual(zip.pathExtension, "zip")
        let folder = zip.deletingPathExtension()
        for name in ["whitebox.obj", "whitebox.mtl", "whitebox.usda", "scene.json", "floorplan.png", "floorplan.pdf", "build_whitebox.py", "AI_README.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), "缺少 \(name)")
        }
        let readme = try String(contentsOf: folder.appendingPathComponent("AI_README.md"), encoding: .utf8)
        XCTAssertFalse(readme.contains("{{"), "README 里还有没替换的占位符")
    }
}
