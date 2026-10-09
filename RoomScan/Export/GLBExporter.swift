import Foundation

/// 白模 → glTF 二进制（.glb）。网页查看器和大多数 AI 3D 工具都认这个格式。
/// glTF 规定 Y 轴朝上、单位米，所以坐标写成 (x, z, -y)；没有写法线，查看器会按平面着色自动计算。
enum GLBExporter {
    private struct MeshData {
        var name: String
        var material: Int
        var positions: [Float] = []
        var indices: [UInt32] = []
    }

    static func export(_ plan: FloorPlanData, whitebox wb: Whitebox) -> Data {
        var meshes: [MeshData] = []
        let boxFaces: [[Int]] = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]

        func push(_ p: Vec3, into m: inout MeshData) {
            m.positions += [Float(p.x), Float(p.z), Float(-p.y)]
        }
        func box(_ b: WhiteboxBox, material: Int) -> MeshData {
            var m = MeshData(name: b.name, material: material)
            b.corners().forEach { push($0, into: &m) }
            for f in boxFaces {
                m.indices += [f[0], f[1], f[2], f[0], f[2], f[3]].map(UInt32.init)
            }
            return m
        }
        func slab(_ s: WhiteboxSlab, material: Int, up: Bool) -> MeshData {
            var m = MeshData(name: s.name, material: material)
            s.polygon.forEach { push(Vec3($0.x, $0.y, s.z), into: &m) }
            for t in Geo.triangulate(s.polygon) {
                m.indices += (up ? t : t.reversed()).map(UInt32.init)
            }
            return m
        }

        meshes += wb.walls.map { box($0, material: 0) }
        meshes += wb.columns.map { box($0, material: 0) }
        meshes += wb.floors.map { slab($0, material: 1, up: true) }
        meshes += wb.ceilings.map { slab($0, material: 2, up: false) }
        meshes.removeAll { $0.indices.isEmpty }

        // 所有数据放进一个 buffer：每个网格一段顶点、一段索引
        var bin = Data()
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var gltfMeshes: [[String: Any]] = []
        var nodes: [[String: Any]] = []

        func align4() { while bin.count % 4 != 0 { bin.append(0) } }

        for (i, m) in meshes.enumerated() {
            align4()
            let posOffset = bin.count
            m.positions.withUnsafeBufferPointer { bin.append(Data(buffer: $0)) }
            bufferViews.append(["buffer": 0, "byteOffset": posOffset, "byteLength": m.positions.count * 4, "target": 34962])
            var mn = [Float](repeating: .greatestFiniteMagnitude, count: 3), mx = [Float](repeating: -.greatestFiniteMagnitude, count: 3)
            for v in 0..<(m.positions.count / 3) {
                for k in 0..<3 {
                    mn[k] = min(mn[k], m.positions[v * 3 + k])
                    mx[k] = max(mx[k], m.positions[v * 3 + k])
                }
            }
            accessors.append(["bufferView": bufferViews.count - 1, "componentType": 5126, "count": m.positions.count / 3,
                              "type": "VEC3", "min": mn, "max": mx])
            let posAccessor = accessors.count - 1

            align4()
            let idxOffset = bin.count
            m.indices.withUnsafeBufferPointer { bin.append(Data(buffer: $0)) }
            bufferViews.append(["buffer": 0, "byteOffset": idxOffset, "byteLength": m.indices.count * 4, "target": 34963])
            accessors.append(["bufferView": bufferViews.count - 1, "componentType": 5125, "count": m.indices.count, "type": "SCALAR"])

            gltfMeshes.append(["name": m.name, "primitives": [["attributes": ["POSITION": posAccessor],
                                                              "indices": accessors.count - 1, "material": m.material]]])
            nodes.append(["name": m.name, "mesh": i])
        }
        align4()

        func mat(_ name: String, _ c: Double) -> [String: Any] {
            ["name": name, "doubleSided": true,
             "pbrMetallicRoughness": ["baseColorFactor": [c, c, c, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.85]]
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Shellplan / AI 装修底图"],
            "scene": 0,
            "scenes": [["name": plan.meta.projectName, "nodes": Array(nodes.indices)]],
            "nodes": nodes,
            "meshes": gltfMeshes,
            "materials": [mat("Wall", 0.95), mat("Floor", 0.8), mat("Ceiling", 0.98)],
            "accessors": accessors,
            "bufferViews": bufferViews,
            "buffers": [["byteLength": bin.count]],
        ]

        var jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        while jsonData.count % 4 != 0 { jsonData.append(0x20) }

        var out = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        u32(0x4654_6C67)                                   // "glTF"
        u32(2)
        u32(UInt32(12 + 8 + jsonData.count + 8 + bin.count))
        u32(UInt32(jsonData.count)); u32(0x4E4F_534A)       // JSON
        out.append(jsonData)
        u32(UInt32(bin.count)); u32(0x004E_4942)            // BIN
        out.append(bin)
        return out
    }
}
