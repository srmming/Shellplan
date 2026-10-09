import Foundation

/// 墙体自动整理：
/// 1. 按整个空间的主方向把墙拉直（短墙段容差更大，它们的角度最容易扫歪）
/// 2. 用相邻墙线的交点重新求墙角，墙和墙严丝合缝
/// 3. 只删真正的噪点（几乎为零长度的墙段），短墙段多半是柱子的一个面，要保留
/// 4. 合并同一直线上相连的墙段
/// 5. 识别贴墙柱（墙「凸出 → 平移 → 缩回」）和独立柱（四段短墙围成一圈）
enum WallCleanup {
    struct Report: Equatable {
        var snapped = 0
        var removed = 0
        var merged = 0
        var pilasters = 0
        var freestanding = 0
    }

    static let longTolerance = 12.0 * .pi / 180
    static let shortTolerance = 35.0 * .pi / 180
    static let shortWall = 0.6

    @discardableResult
    static func run(_ plan: inout FloorPlanData) -> Report {
        var report = Report()
        guard !plan.walls.isEmpty else { return report }
        plan.recomputeDerived()

        // 门窗的世界坐标先记下来，墙变了以后再挂回去
        let openingCenters: [String: Vec2] = Dictionary(uniqueKeysWithValues: plan.openings.compactMap { o in
            guard let w = plan.wall(o.wallId) else { return nil }
            return (o.id, w.start + w.direction * o.centerOffset)
        })

        report.snapped = straighten(&plan)
        report.removed = removeNoise(&plan)
        report.merged = mergeCollinear(&plan)
        reattachOpenings(&plan, centers: openingCenters)
        plan.recomputeDerived()

        // 自动识别的柱子每次重新识别，手动加的保留
        plan.columns.removeAll { $0.source == "detected" }
        report.freestanding = detectFreestanding(&plan)
        report.pilasters = detectPilasters(&plan)
        return report
    }

    // MARK: - 拉直 + 重算墙角

    private struct Line {
        var point: Vec2
        var dir: Vec2
        var normal: Vec2 { dir.perpendicular }
    }

    /// 主方向：以每面墙的角度为候选，取「2° 以内的墙总长最大」的那个，再用这些墙求平均。
    /// 这样一面扫歪的长墙不会把整个房间带偏。
    static func dominantAngle(_ walls: [FloorPlanData.Wall]) -> Double {
        let angles = walls.map { w -> (a: Double, len: Double) in
            (atan2(w.end.y - w.start.y, w.end.x - w.start.x), w.length)
        }
        func diff90(_ a: Double, _ b: Double) -> Double {
            var d = (a - b).truncatingRemainder(dividingBy: .pi / 2)
            if d > .pi / 4 { d -= .pi / 2 }
            if d < -.pi / 4 { d += .pi / 2 }
            return d
        }
        let tol = 2.0 * .pi / 180
        var best = angles.first?.a ?? 0
        var bestScore = -1.0
        for cand in angles {
            let score = angles.filter { abs(diff90($0.a, cand.a)) < tol }.reduce(0) { $0 + $1.len }
            if score > bestScore { bestScore = score; best = cand.a }
        }
        let inliers = angles.filter { abs(diff90($0.a, best)) < tol }
        let total = inliers.reduce(0) { $0 + $1.len }
        let mean = inliers.reduce(0) { $0 + diff90($1.a, best) * $1.len } / max(total, 1e-9)
        return best + mean
    }

    private static func wrap(_ a: Double) -> Double {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x <= -.pi { x += 2 * .pi }
        return x
    }

    /// 把端点聚成节点（距离 < 5cm 的端点算同一个墙角）
    private static func buildNodes(_ walls: [FloorPlanData.Wall]) -> (nodes: [Vec2], ends: [(Int, Int)]) {
        var nodes: [Vec2] = []
        func node(_ p: Vec2) -> Int {
            if let i = nodes.firstIndex(where: { ($0 - p).length < 0.05 }) { return i }
            nodes.append(p)
            return nodes.count - 1
        }
        let ends = walls.map { (node($0.start), node($0.end)) }
        return (nodes, ends)
    }

    private static func straighten(_ plan: inout FloorPlanData) -> Int {
        let walls = plan.walls
        let theta = dominantAngle(walls)
        var snapped = 0
        var lines: [Line] = walls.map { w in
            let a = atan2(w.end.y - w.start.y, w.end.x - w.start.x)
            var best = a
            var bestDiff = Double.infinity
            for k in 0..<4 {
                let cand = theta + Double(k) * .pi / 2
                let diff = abs(wrap(a - cand))
                if diff < bestDiff { bestDiff = diff; best = cand }
            }
            let tol = w.length < shortWall ? shortTolerance : longTolerance
            guard bestDiff <= tol else { return Line(point: w.midpoint, dir: w.direction) }
            if bestDiff > 0.2 * .pi / 180 { snapped += 1 }
            // 方向保持和原来同向
            var d = Vec2(cos(best), sin(best))
            if d.dot(w.direction) < 0 { d = d * -1 }
            return Line(point: w.midpoint, dir: d)
        }

        // 几乎在同一直线上的墙（同方向、偏差 < 3cm）对齐到同一条线，墙角才能严丝合缝
        var groups: [[Int]] = []
        for i in lines.indices {
            if let g = groups.firstIndex(where: { g in
                let l = lines[g[0]]
                return abs(l.dir.x * lines[i].dir.y - l.dir.y * lines[i].dir.x) < 1e-6
                    && abs((lines[i].point - l.point).dot(l.normal)) < 0.03
            }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        for g in groups where g.count > 1 {
            let n = lines[g[0]].normal
            let total = g.reduce(0.0) { $0 + walls[$1].length }
            let offset = g.reduce(0.0) { $0 + n.dot(lines[$1].point) * walls[$1].length } / max(total, 1e-9)
            for i in g {
                let p = lines[i].point
                lines[i].point = p + n * (offset - n.dot(p))
            }
        }

        let (nodes, ends) = buildNodes(walls)
        var incident: [[Int]] = Array(repeating: [], count: nodes.count)
        for (i, e) in ends.enumerated() {
            incident[e.0].append(i)
            if e.1 != e.0 { incident[e.1].append(i) }
        }

        var solved = nodes
        for n in nodes.indices {
            var ls = incident[n].map { lines[$0] }
            // T 字形接头：只有一面墙的端点，如果贴在另一面墙的中段，把那面墙的线也算进来
            if incident[n].count == 1 {
                let own = incident[n][0]
                for (j, w) in walls.enumerated() where j != own {
                    if Geo.distance(nodes[n], segment: w.start, w.end) < 0.1 { ls.append(lines[j]) }
                }
            }
            solved[n] = intersect(ls, near: nodes[n])
        }

        for i in plan.walls.indices {
            plan.walls[i].start = solved[ends[i].0]
            plan.walls[i].end = solved[ends[i].1]
        }
        return snapped
    }

    /// 最小二乘求多条直线的交点；直线都平行时退回到投影
    private static func intersect(_ lines: [Line], near p: Vec2) -> Vec2 {
        guard !lines.isEmpty else { return p }
        var a11 = 0.0, a12 = 0.0, a22 = 0.0, b1 = 0.0, b2 = 0.0
        for l in lines {
            let n = l.normal
            let c = n.dot(l.point)
            a11 += n.x * n.x; a12 += n.x * n.y; a22 += n.y * n.y
            b1 += n.x * c; b2 += n.y * c
        }
        let det = a11 * a22 - a12 * a12
        // 两条直线夹角小于约 20° 就当作平行
        if det > 0.1 * Double(lines.count) {
            return Vec2((a22 * b1 - a12 * b2) / det, (a11 * b2 - a12 * b1) / det)
        }
        let l = lines[0]
        return l.point + l.dir * (p - l.point).dot(l.dir)
    }

    // MARK: - 去噪 / 合并

    private static func removeNoise(_ plan: inout FloorPlanData) -> Int {
        let before = plan.walls.count
        let noise = Set(plan.walls.filter { ($0.end - $0.start).length < 0.02 }.map(\.id))
        plan.walls.removeAll { noise.contains($0.id) }
        return before - plan.walls.count
    }

    private static func mergeCollinear(_ plan: inout FloorPlanData) -> Int {
        var merged = 0
        var changed = true
        while changed {
            changed = false
            let (nodes, ends) = buildNodes(plan.walls)
            var incident: [[Int]] = Array(repeating: [], count: nodes.count)
            for (i, e) in ends.enumerated() {
                incident[e.0].append(i)
                incident[e.1].append(i)
            }
            for n in nodes.indices where incident[n].count == 2 {
                let i = incident[n][0], j = incident[n][1]
                guard i != j else { continue }
                let a = plan.walls[i], b = plan.walls[j]
                let da = (a.end - a.start).normalized, db = (b.end - b.start).normalized
                let cross = abs(da.x * db.y - da.y * db.x)
                guard cross < sin(1.0 * .pi / 180),
                      abs(a.height - b.height) < 0.03,
                      Set(a.roomIds) == Set(b.roomIds),
                      // 有别的墙以 T 字形接在这个节点上就不合并
                      !plan.walls.indices.contains(where: { k in
                          k != i && k != j && Geo.distance(nodes[n], segment: plan.walls[k].start, plan.walls[k].end) < 0.03
                      }) else { continue }
                let farA = ends[i].0 == n ? a.end : a.start
                let farB = ends[j].0 == n ? b.end : b.start
                plan.walls[i].start = farA
                plan.walls[i].end = farB
                plan.walls[i].measuredLength = nil
                plan.walls.remove(at: j)
                merged += 1
                changed = true
                break
            }
        }
        return merged
    }

    /// 门窗按原来的世界坐标重新挂到最近的墙上
    private static func reattachOpenings(_ plan: inout FloorPlanData, centers: [String: Vec2]) {
        for i in plan.openings.indices {
            guard let c = centers[plan.openings[i].id] else { continue }
            let current = plan.wall(plan.openings[i].wallId)
            let wall: FloorPlanData.Wall?
            if let current, Geo.distance(c, segment: current.start, current.end) < 0.2 {
                wall = current
            } else {
                wall = plan.walls.min {
                    Geo.distance(c, segment: $0.start, $0.end) < Geo.distance(c, segment: $1.start, $1.end)
                }
            }
            guard let w = wall else { continue }
            let len = (w.end - w.start).length
            let half = plan.openings[i].width / 2
            plan.openings[i].wallId = w.id
            plan.openings[i].centerOffset = min(max((c - w.start).dot(w.direction), half), max(len - half, half))
        }
    }

    // MARK: - 柱子识别

    private static func neighbors(_ plan: FloorPlanData) -> (nodes: [Vec2], ends: [(Int, Int)], incident: [[Int]]) {
        let (nodes, ends) = buildNodes(plan.walls)
        var incident: [[Int]] = Array(repeating: [], count: nodes.count)
        for (i, e) in ends.enumerated() {
            incident[e.0].append(i)
            incident[e.1].append(i)
        }
        return (nodes, ends, incident)
    }

    private static func parallel(_ a: FloorPlanData.Wall, _ b: FloorPlanData.Wall) -> Bool {
        let da = a.direction, db = b.direction
        return abs(da.x * db.y - da.y * db.x) < 0.1
    }

    private static func perpendicular(_ a: FloorPlanData.Wall, _ b: FloorPlanData.Wall) -> Bool {
        abs(a.direction.dot(b.direction)) < 0.1
    }

    /// 贴墙柱：P1 —— S1（凸出）—— F（柱面）—— S2（缩回）—— P2，且 P1、P2 在同一直线上，F 凸向房间里
    private static func detectPilasters(_ plan: inout FloorPlanData) -> Int {
        let (_, ends, incident) = neighbors(plan)
        let walls = plan.walls
        // 已经算作独立柱的墙不再参与
        let taken = Set(plan.columns.flatMap(\.wallIds))
        var used = Set(walls.indices.filter { taken.contains(walls[$0].id) })
        var found = 0

        func other(at node: Int, than wall: Int) -> Int? {
            let others = incident[node].filter { $0 != wall }
            return others.count == 1 ? others[0] : nil
        }
        func farNode(of wall: Int, from node: Int) -> Int { ends[wall].0 == node ? ends[wall].1 : ends[wall].0 }

        for f in walls.indices where walls[f].length <= 1.2 && !used.contains(f) {
            let (n0, n1) = ends[f]
            guard let s1 = other(at: n0, than: f), let s2 = other(at: n1, than: f),
                  s1 != s2, !used.contains(s1), !used.contains(s2) else { continue }
            let F = walls[f], S1 = walls[s1], S2 = walls[s2]
            guard perpendicular(F, S1), perpendicular(F, S2),
                  (0.04...1.0).contains(S1.length), (0.04...1.0).contains(S2.length),
                  abs(S1.length - S2.length) <= 0.08 else { continue }
            guard let p1 = other(at: farNode(of: s1, from: n0), than: s1),
                  let p2 = other(at: farNode(of: s2, from: n1), than: s2),
                  p1 != f, p2 != f, p1 != p2 else { continue }
            let P1 = walls[p1], P2 = walls[p2]
            guard parallel(P1, F), parallel(P2, F) else { continue }
            // P1、P2 同一直线
            let pn = P1.direction.perpendicular
            guard abs((P2.midpoint - P1.midpoint).dot(pn)) < 0.06 else { continue }
            // F 要凸向房间里，否则是凹进去的壁龛
            let toFace = (F.midpoint - P1.midpoint).dot(pn)
            let roomSide = (P1.outward * -1).dot(pn)
            guard toFace * roomSide > 0 else { continue }

            let depth = (S1.length + S2.length) / 2
            let center = F.midpoint - pn * (toFace / 2)
            plan.columns.append(FloorPlanData.Column(
                id: "C\(plan.columns.count + 1)", kind: .pilaster, center: center,
                width: F.length, depth: depth, yaw: atan2(F.direction.y, F.direction.x),
                height: max(F.height, S1.height, S2.height), wallIds: [S1.id, F.id, S2.id], source: "detected"))
            used.formUnion([f, s1, s2])
            found += 1
        }
        return found
    }

    /// 独立柱：四段短墙首尾相连围成一圈，而且不和其他墙相连
    private static func detectFreestanding(_ plan: inout FloorPlanData) -> Int {
        let (_, ends, incident) = neighbors(plan)
        let walls = plan.walls
        var visited = Set<Int>()
        var found = 0
        for start in walls.indices where !visited.contains(start) {
            // 连通分量
            var comp: [Int] = []
            var stack = [start]
            while let w = stack.popLast() {
                guard !visited.contains(w) else { continue }
                visited.insert(w)
                comp.append(w)
                for n in [ends[w].0, ends[w].1] { stack.append(contentsOf: incident[n].filter { !visited.contains($0) }) }
            }
            guard comp.count == 4, comp.allSatisfy({ walls[$0].length <= 1.2 }),
                  comp.allSatisfy({ i in [ends[i].0, ends[i].1].allSatisfy { incident[$0].count == 2 } }) else { continue }
            let pts = comp.flatMap { [walls[$0].start, walls[$0].end] }
            let center = pts.reduce(Vec2(0, 0), +) * (1.0 / Double(pts.count))
            let a = walls[comp[0]], b = comp.map { walls[$0] }.first { perpendicular($0, a) } ?? a
            plan.columns.append(FloorPlanData.Column(
                id: "C\(plan.columns.count + 1)", kind: .freestanding, center: center,
                width: a.length, depth: b.length, yaw: atan2(a.direction.y, a.direction.x),
                height: comp.map { walls[$0].height }.max() ?? 2.7, wallIds: comp.map { walls[$0].id }, source: "detected"))
            found += 1
        }
        return found
    }
}
