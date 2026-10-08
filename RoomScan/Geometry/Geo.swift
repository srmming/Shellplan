import Foundation

/// 平面几何工具
enum Geo {
    static func signedArea(_ p: [Vec2]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func polygonArea(_ p: [Vec2]) -> Double { abs(signedArea(p)) }

    static func ensureCCW(_ p: [Vec2]) -> [Vec2] { signedArea(p) < 0 ? p.reversed() : p }

    static func centroid(_ p: [Vec2]) -> Vec2 {
        guard !p.isEmpty else { return Vec2(0, 0) }
        let a = signedArea(p)
        if abs(a) < 1e-9 {
            let sum = p.reduce(Vec2(0, 0), +)
            return sum * (1.0 / Double(p.count))
        }
        var cx = 0.0, cy = 0.0
        for i in p.indices {
            let s = p[i], t = p[(i + 1) % p.count]
            let f = s.x * t.y - t.x * s.y
            cx += (s.x + t.x) * f
            cy += (s.y + t.y) * f
        }
        return Vec2(cx / (6 * a), cy / (6 * a))
    }

    static func distance(_ p: Vec2, segment a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let len2 = ab.dot(ab)
        guard len2 > 1e-12 else { return (p - a).length }
        let t = min(max((p - a).dot(ab) / len2, 0), 1)
        return (p - (a + ab * t)).length
    }

    static func distanceToEdges(_ p: Vec2, polygon: [Vec2]) -> Double {
        guard polygon.count >= 2 else { return .infinity }
        var best = Double.infinity
        for i in polygon.indices {
            best = min(best, distance(p, segment: polygon[i], polygon[(i + 1) % polygon.count]))
        }
        return best
    }

    static func pointInPolygon(_ p: Vec2, _ poly: [Vec2]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// 没有地面轮廓时，用墙的端点按角度排序拼出一个近似轮廓
    static func polygonFromSegments(_ segs: [(Vec2, Vec2)]) -> [Vec2] {
        var pts: [Vec2] = []
        for (a, b) in segs {
            for p in [a, b] where !pts.contains(where: { ($0 - p).length < 0.15 }) {
                pts.append(p)
            }
        }
        guard pts.count >= 3 else { return pts }
        let c = pts.reduce(Vec2(0, 0), +) * (1.0 / Double(pts.count))
        return pts.sorted { atan2($0.y - c.y, $0.x - c.x) < atan2($1.y - c.y, $1.x - c.x) }
    }

    /// 耳切法三角化，返回顶点下标三元组（逆时针）
    static func triangulate(_ poly: [Vec2]) -> [[Int]] {
        guard poly.count >= 3 else { return [] }
        var idx = Array(poly.indices)
        if signedArea(poly) < 0 { idx.reverse() }
        var tris: [[Int]] = []
        var guardCount = 0
        while idx.count > 3 && guardCount < 10_000 {
            guardCount += 1
            var clipped = false
            for i in idx.indices {
                let a = idx[(i + idx.count - 1) % idx.count], b = idx[i], c = idx[(i + 1) % idx.count]
                let pa = poly[a], pb = poly[b], pc = poly[c]
                let cross = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x)
                if cross <= 1e-12 { continue }
                let blocked = idx.contains { j in
                    j != a && j != b && j != c && pointInTriangle(poly[j], pa, pb, pc)
                }
                if blocked { continue }
                tris.append([a, b, c])
                idx.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break }
        }
        if idx.count == 3 {
            tris.append(idx)
        } else if idx.count > 3 {
            // 退化多边形：扇形兜底
            for i in 1..<(idx.count - 1) { tris.append([idx[0], idx[i], idx[i + 1]]) }
        }
        return tris
    }

    private static func pointInTriangle(_ p: Vec2, _ a: Vec2, _ b: Vec2, _ c: Vec2) -> Bool {
        func sign(_ p1: Vec2, _ p2: Vec2, _ p3: Vec2) -> Double {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }
}
