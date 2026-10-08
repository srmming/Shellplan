import Foundation

/// 白模 → Wavefront OBJ。
/// 文件按 OBJ 惯例写成 Y 轴朝上（x, z, -y）；Blender 默认导入设置（前 -Z、上 Y）会还原成 Z 轴朝上，
/// 导入后的坐标和 scene.json 完全一致。
enum OBJExporter {
    static func export(_ plan: FloorPlanData, whitebox wb: Whitebox) -> (obj: String, mtl: String) {
        var out = "# RoomScan whitebox — \(plan.meta.projectName)\n# Units: meters. Written Y-up; Blender's default OBJ import restores the Z-up coordinates of scene.json\n"
        out += "mtllib whitebox.mtl\n"
        var vertexCount = 0

        func v(_ p: Vec3) -> String { String(format: "v %.4f %.4f %.4f\n", p.x, p.z, -p.y) }

        func writeBox(_ box: WhiteboxBox, material: String) {
            out += "o \(box.name)\nusemtl \(material)\n"
            for c in box.corners() { out += v(c) }
            let b = vertexCount + 1
            for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]] {
                out += "f " + f.map { String(b + $0) }.joined(separator: " ") + "\n"
            }
            vertexCount += 8
        }

        func writeSlab(_ slab: WhiteboxSlab, material: String, facingUp: Bool) {
            out += "o \(slab.name)\nusemtl \(material)\n"
            for p in slab.polygon { out += v(Vec3(p.x, p.y, slab.z)) }
            let b = vertexCount + 1
            for tri in Geo.triangulate(slab.polygon) {
                let ordered = facingUp ? tri : tri.reversed()
                out += "f " + ordered.map { String(b + $0) }.joined(separator: " ") + "\n"
            }
            vertexCount += slab.polygon.count
        }

        for box in wb.walls { writeBox(box, material: "Wall") }
        for slab in wb.floors { writeSlab(slab, material: "Floor", facingUp: true) }
        for slab in wb.ceilings { writeSlab(slab, material: "Ceiling", facingUp: false) }
        for box in wb.fixtures { writeBox(box, material: "Reference") }

        let mtl = """
        # RoomScan 白模材质
        newmtl Wall
        Kd 0.95 0.95 0.95
        newmtl Floor
        Kd 0.80 0.80 0.80
        newmtl Ceiling
        Kd 0.98 0.98 0.98
        newmtl Reference
        Kd 0.40 0.70 0.75
        d 0.6

        """
        return (out, mtl)
    }
}
