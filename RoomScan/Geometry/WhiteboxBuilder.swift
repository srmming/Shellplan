import Foundation

/// 一个有朝向的长方体：x = 沿 yaw 方向的长度，y = 厚度/深度，z = 高度
struct WhiteboxBox: Equatable {
    var name: String
    var ownerId: String
    var center: Vec3
    var size: Vec3
    var yaw: Double

    /// 8 个角点：0-3 底面（从上往下看逆时针），4-7 顶面
    func corners() -> [Vec3] {
        let c = cos(yaw), s = sin(yaw)
        var out: [Vec3] = []
        for dz in [-0.5, 0.5] {
            for (dx, dy) in [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)] {
                let lx = dx * size.x, ly = dy * size.y
                out.append(Vec3(center.x + lx * c - ly * s, center.y + lx * s + ly * c, center.z + dz * size.z))
            }
        }
        return out
    }
}

/// 地面 / 天花板
struct WhiteboxSlab: Equatable {
    var name: String
    var roomId: String
    var polygon: [Vec2]
    var z: Double
}

struct Whitebox {
    var walls: [WhiteboxBox]
    var floors: [WhiteboxSlab]
    var ceilings: [WhiteboxSlab]
    var fixtures: [WhiteboxBox]
}

/// FloorPlanData → 带真实门窗洞口的白模几何。3D 查看、OBJ 导出共用这一份结果；
/// Resources/build_whitebox.py 里的 wall_pieces 与这里的算法保持一致。
enum WhiteboxBuilder {
    struct Piece: Equatable {
        var u0: Double, u1: Double, z0: Double, z1: Double
    }

    /// 把一面墙按洞口切成若干实心块。u 是沿墙方向距离起点的长度，z 是离地高度。
    static func pieces(length: Double, height: Double, openings: [FloorPlanData.Opening]) -> [Piece] {
        let eps = 0.005
        var spans: [Piece] = []
        for o in openings {
            let a = max(0, o.centerOffset - o.width / 2)
            let b = min(length, o.centerOffset + o.width / 2)
            let z0 = max(0, o.sillHeight)
            let z1 = min(height, o.sillHeight + o.height)
            if b - a > 0.01 && z1 - z0 > 0.01 { spans.append(Piece(u0: a, u1: b, z0: z0, z1: z1)) }
        }
        spans.sort { $0.u0 < $1.u0 }

        var result: [Piece] = []
        var cursor = 0.0
        for span in spans {
            let a = max(span.u0, cursor)
            if a > cursor + eps { result.append(Piece(u0: cursor, u1: a, z0: 0, z1: height)) }
            if span.u1 > a + eps {
                if span.z0 > eps { result.append(Piece(u0: a, u1: span.u1, z0: 0, z1: span.z0)) }
                if span.z1 < height - eps { result.append(Piece(u0: a, u1: span.u1, z0: span.z1, z1: height)) }
            }
            cursor = max(cursor, span.u1)
        }
        if cursor < length - eps { result.append(Piece(u0: cursor, u1: length, z0: 0, z1: height)) }
        return result
    }

    /// 墙向外挤出厚度后，外转角会缺一个方块。端点处如果接着另一面墙、且那面墙朝本墙的室内一侧走（外转角），
    /// 就把本墙在这一端延长对方的墙厚，把角补上。内转角不延长，避免伸进房间。
    static func endExtensions(_ wall: FloorPlanData.Wall, plan: FloorPlanData) -> (start: Double, end: Double) {
        func ext(at p: Vec2) -> Double {
            var best = 0.0
            for other in plan.walls where other.id != wall.id {
                let away: Vec2
                if (other.start - p).length < 0.2 {
                    away = other.direction
                } else if (other.end - p).length < 0.2 {
                    away = other.direction * -1
                } else {
                    continue
                }
                if away.dot(wall.outward) < -0.5 { best = max(best, other.thickness) }
            }
            return best
        }
        return (ext(at: wall.start), ext(at: wall.end))
    }

    static func build(_ plan: FloorPlanData) -> Whitebox {
        var walls: [WhiteboxBox] = []
        for wall in plan.walls {
            let dir = wall.direction
            let yaw = atan2(dir.y, dir.x)
            let shift = wall.outward * (wall.thickness / 2)
            var parts = pieces(length: wall.length, height: wall.height, openings: plan.openings(on: wall.id))
            let (extStart, extEnd) = endExtensions(wall, plan: plan)
            for i in parts.indices {
                if parts[i].u0 <= 0.001 { parts[i].u0 = -extStart }
                if parts[i].u1 >= wall.length - 0.001 { parts[i].u1 = wall.length + extEnd }
            }
            for (i, p) in parts.enumerated() {
                let along = wall.start + dir * ((p.u0 + p.u1) / 2) + shift
                walls.append(WhiteboxBox(
                    name: "Wall_\(wall.id)_\(i + 1)",
                    ownerId: wall.id,
                    center: Vec3(along.x, along.y, (p.z0 + p.z1) / 2),
                    size: Vec3(p.u1 - p.u0, wall.thickness, p.z1 - p.z0),
                    yaw: yaw
                ))
            }
        }

        let floors = plan.rooms.filter { $0.floorPolygon.count >= 3 }.map {
            WhiteboxSlab(name: "Floor_\($0.id)", roomId: $0.id, polygon: $0.floorPolygon, z: 0)
        }
        let ceilings = plan.rooms.filter { $0.floorPolygon.count >= 3 }.map {
            WhiteboxSlab(name: "Ceiling_\($0.id)", roomId: $0.id, polygon: $0.floorPolygon, z: $0.height)
        }
        let fixtures = plan.fixtures.map {
            WhiteboxBox(name: "Ref_\($0.category)_\($0.id)", ownerId: $0.id, center: $0.center, size: $0.size, yaw: $0.yaw)
        }
        return Whitebox(walls: walls, floors: floors, ceilings: ceilings, fixtures: fixtures)
    }
}
