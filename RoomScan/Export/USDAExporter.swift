import Foundation

/// 白模 → USD 文本格式（.usda）。直接写 Z 轴朝上、单位米，和 scene.json 坐标完全一致，Blender 可以原生导入。
/// 不用 SceneKit 的 USDZ 导出：它在 iOS 上处理某些几何体时会在系统框架内部崩溃。
enum USDAExporter {
    static func export(_ plan: FloorPlanData, whitebox wb: Whitebox) -> String {
        var out = """
        #usda 1.0
        (
            defaultPrim = "Whitebox"
            metersPerUnit = 1
            upAxis = "Z"
            doc = "Shellplan whitebox: \(plan.meta.projectName.replacingOccurrences(of: "\"", with: "'"))"
        )

        def Xform "Whitebox"
        {

        """

        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        func points(_ ps: [Vec3]) -> String { ps.map { "(\(f($0.x)), \(f($0.y)), \(f($0.z)))" }.joined(separator: ", ") }

        func mesh(_ name: String, points ps: [Vec3], faces: [[Int]], color: (Double, Double, Double), indent: String) -> String {
            """
            \(indent)def Mesh "\(primName(name))"
            \(indent){
            \(indent)    int[] faceVertexCounts = [\(faces.map { String($0.count) }.joined(separator: ", "))]
            \(indent)    int[] faceVertexIndices = [\(faces.flatMap { $0 }.map(String.init).joined(separator: ", "))]
            \(indent)    point3f[] points = [\(points(ps))]
            \(indent)    color3f[] primvars:displayColor = [(\(f(color.0)), \(f(color.1)), \(f(color.2)))]
            \(indent)    uniform token subdivisionScheme = "none"
            \(indent)}

            """
        }

        let boxFaces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]

        func scope(_ name: String, _ body: String) -> String {
            guard !body.isEmpty else { return "" }
            return "    def Scope \"\(name)\"\n    {\n\(body)    }\n\n"
        }

        out += scope("Walls", wb.walls.map {
            mesh($0.name, points: $0.corners(), faces: boxFaces, color: (0.95, 0.95, 0.95), indent: "        ")
        }.joined())

        out += scope("Floors", wb.floors.map { slab in
            mesh(slab.name, points: slab.polygon.map { Vec3($0.x, $0.y, slab.z) },
                 faces: Geo.triangulate(slab.polygon), color: (0.8, 0.8, 0.8), indent: "        ")
        }.joined())

        out += scope("Ceilings", wb.ceilings.map { slab in
            mesh(slab.name, points: slab.polygon.map { Vec3($0.x, $0.y, slab.z) },
                 faces: Geo.triangulate(slab.polygon).map { $0.reversed() }, color: (0.98, 0.98, 0.98), indent: "        ")
        }.joined())

        out += scope("Fixtures_Ref", wb.fixtures.map {
            mesh($0.name, points: $0.corners(), faces: boxFaces, color: (0.4, 0.7, 0.75), indent: "        ")
        }.joined())

        out += "}\n"
        return out
    }

    /// USD 的 prim 名只能用字母、数字和下划线，且不能以数字开头
    static func primName(_ s: String) -> String {
        var r = String(s.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" })
        if let first = r.first, first.isNumber { r = "_" + r }
        return r.isEmpty ? "_" : r
    }
}
