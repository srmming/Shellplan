import UIKit

/// 平面图在画布上的摆放：比例、偏移，以及平面坐标和画布坐标的互相换算
struct PlanLayout {
    let rect: CGRect
    /// 字号、线宽的基准倍数
    let k: CGFloat
    let margin: CGFloat
    /// 每米多少画布单位
    let s: CGFloat
    let ox: CGFloat, oy: CGFloat
    let bmin: Vec2, bmax: Vec2

    /// compact：App 里看的平面图，页边距和标题更小、字号按屏幕点数算
    init(plan: FloorPlanData, rect: CGRect, compact: Bool = false) {
        self.rect = rect
        k = compact ? 0.95 : rect.width / 1000
        margin = (compact ? 34 : 80) * k
        let titleH = (compact ? 46 : 64) * k
        let b = plan.bounds
        bmin = b.min
        bmax = b.max
        let bw = max(b.max.x - b.min.x, 0.5), bh = max(b.max.y - b.min.y, 0.5)
        let avail = CGRect(x: rect.minX + margin, y: rect.minY + titleH + margin,
                           width: rect.width - 2 * margin, height: rect.height - titleH - 2 * margin)
        s = max(min(avail.width / bw, avail.height / bh), 1)
        ox = avail.minX + (avail.width - bw * s) / 2
        oy = avail.minY + (avail.height - bh * s) / 2
    }

    func pt(_ p: Vec2) -> CGPoint { CGPoint(x: ox + (p.x - bmin.x) * s, y: oy + (bmax.y - p.y) * s) }
    func planPoint(_ c: CGPoint) -> Vec2 { Vec2(bmin.x + (c.x - ox) / s, bmax.y - (c.y - oy) / s) }
}

/// 在平面图上点到了什么
enum PlanHit {
    case opening(String)
    case wall(String, Vec2)
    case nothing
}

/// 俯视尺寸平面图（单位 mm）。App 里的平面图页面、导出的 PNG / PDF 都用这一个绘制函数。
enum FloorPlanRenderer {
    static func image(_ plan: FloorPlanData, highlightRoomId: String? = nil, width: CGFloat = 2400) -> UIImage {
        let size = canvasSize(plan, width: width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(plan, in: ctx.cgContext, layout: PlanLayout(plan: plan, rect: CGRect(origin: .zero, size: size)),
                 highlightRoomId: highlightRoomId)
        }
    }

    /// App 里看的平面图：按视图尺寸出图，铺满屏幕
    static func screenImage(_ plan: FloorPlanData, size: CGSize, scale: CGFloat, highlightRoomId: String?,
                            selectedOpeningId: String?, selectedWallId: String?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(plan, in: ctx.cgContext, layout: screenLayout(plan, size: size), highlightRoomId: highlightRoomId,
                 selectedOpeningId: selectedOpeningId, selectedWallId: selectedWallId)
        }
    }

    static func screenLayout(_ plan: FloorPlanData, size: CGSize) -> PlanLayout {
        PlanLayout(plan: plan, rect: CGRect(origin: .zero, size: size), compact: true)
    }

    /// 点击命中：先找门窗，再找墙
    static func hitTest(_ plan: FloorPlanData, layout: PlanLayout, at point: CGPoint) -> PlanHit {
        let p = layout.planPoint(point)
        let tolerance = max(24 / layout.s, 0.12)
        var best: (Double, PlanHit) = (.infinity, .nothing)
        for o in plan.openings {
            guard let (a, b) = plan.segment(of: o), let w = plan.wall(o.wallId) else { continue }
            let shift = w.outward * (w.thickness / 2)
            let d = Geo.distance(p, segment: a + shift, b + shift)
            if d < tolerance + w.thickness, d < best.0 { best = (d, .opening(o.id)) }
        }
        if case .opening = best.1 { return best.1 }
        for w in plan.walls {
            let shift = w.outward * (w.thickness / 2)
            let d = Geo.distance(p, segment: w.start + shift, w.end + shift)
            if d < tolerance + w.thickness / 2, d < best.0 {
                let t = min(max((p - w.start).dot(w.direction), 0), w.length)
                best = (d, .wall(w.id, w.start + w.direction * t))
            }
        }
        return best.1
    }

    /// A3 横向
    static func pdfData(_ plan: FloorPlanData) -> Data {
        let page = CGRect(x: 0, y: 0, width: 1191, height: 842)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            ctx.beginPage()
            draw(plan, in: ctx.cgContext, layout: PlanLayout(plan: plan, rect: page), highlightRoomId: nil)
        }
    }

    static func canvasSize(_ plan: FloorPlanData, width: CGFloat) -> CGSize {
        let b = plan.bounds
        let w = max(b.max.x - b.min.x, 1), h = max(b.max.y - b.min.y, 1)
        let aspect = min(max(h / w, 0.55), 1.6)
        return CGSize(width: width, height: (width * aspect + width * 0.1).rounded())
    }

    static func draw(_ plan: FloorPlanData, in ctx: CGContext, layout: PlanLayout, highlightRoomId: String?,
                     selectedOpeningId: String? = nil, selectedWallId: String? = nil) {
        let rect = layout.rect
        UIColor.white.setFill()
        ctx.fill(rect)

        let k = layout.k
        let margin = layout.margin
        let s = layout.s
        let selectColor = UIColor.systemOrange
        func pt(_ p: Vec2) -> CGPoint { layout.pt(p) }

        // 标题
        text(plan.meta.projectName, at: CGPoint(x: rect.minX + margin, y: rect.minY + 30 * k),
             font: .systemFont(ofSize: 24 * k, weight: .semibold), color: .black, align: .left, ctx: ctx)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sub = String(localized: "\(plan.rooms.count) 个房间 · 总面积 \(Fmt.area(plan.totalArea)) ㎡ · 尺寸单位 mm · \(df.string(from: plan.meta.createdAt))")
        text(sub, at: CGPoint(x: rect.minX + margin, y: rect.minY + 58 * k),
             font: .systemFont(ofSize: 13 * k), color: .darkGray, align: .left, ctx: ctx)

        // 房间底色
        for room in plan.rooms where room.floorPolygon.count >= 3 {
            let path = CGMutablePath()
            path.addLines(between: room.floorPolygon.map(pt))
            path.closeSubpath()
            ctx.addPath(path)
            let fill = room.id == highlightRoomId ? UIColor(red: 0.88, green: 0.94, blue: 1, alpha: 1) : UIColor(white: 0.965, alpha: 1)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }

        // 固定设施（虚线框）
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [4 * k, 3 * k])
        for f in plan.fixtures {
            let c = cos(f.yaw), sn = sin(f.yaw)
            let corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].map { dx, dy -> CGPoint in
                let lx = dx * f.size.x, ly = dy * f.size.y
                return pt(Vec2(f.center.x + lx * c - ly * sn, f.center.y + lx * sn + ly * c))
            }
            let path = CGMutablePath()
            path.addLines(between: corners)
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setStrokeColor(UIColor.systemTeal.cgColor)
            ctx.setLineWidth(1.2 * k)
            ctx.strokePath()
            text(f.name, at: pt(f.center.xy), font: .systemFont(ofSize: 9 * k), color: .systemTeal, ctx: ctx)
        }
        ctx.restoreGState()

        // 墙
        let wallColor = UIColor(white: 0.15, alpha: 1).cgColor
        for w in plan.walls {
            let off = w.outward * (w.thickness / 2)
            ctx.setStrokeColor(w.id == selectedWallId ? selectColor.cgColor : wallColor)
            ctx.setLineWidth(max(w.thickness * s, 3 * k))
            ctx.setLineCap(.square)
            ctx.move(to: pt(w.start + off))
            ctx.addLine(to: pt(w.end + off))
            ctx.strokePath()
        }

        // 门窗：按样式画
        for o in plan.openings {
            guard let w = plan.wall(o.wallId), let (p0, p1) = plan.segment(of: o) else { continue }
            let t = w.thickness
            let off = w.outward * (t / 2)
            let wallWidth = max(t * s, 3 * k)
            let selected = o.id == selectedOpeningId
            let doorColor = selected ? selectColor : UIColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1)
            let windowColor = selected ? selectColor : UIColor.systemBlue

            // 先把墙上的洞口擦白
            ctx.setLineCap(.butt)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(wallWidth + 2 * k)
            ctx.move(to: pt(p0 + off))
            ctx.addLine(to: pt(p1 + off))
            ctx.strokePath()

            /// 沿洞口方向从 a 到 b（0…1）、在墙厚方向 f（0 = 室内墙面，1 = 室外墙面）画一条线
            func line(_ a: Double, _ b: Double, at f: Double, color: UIColor, width: CGFloat) {
                let shift = w.outward * (t * f)
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(width)
                ctx.move(to: pt(p0 + (p1 - p0) * a + shift))
                ctx.addLine(to: pt(p0 + (p1 - p0) * b + shift))
                ctx.strokePath()
            }

            switch (o.kind, o.style) {
            case (.door, .slidingDoor):
                line(0, 0.55, at: 0.3, color: doorColor, width: 2.2 * k)
                line(0.45, 1, at: 0.7, color: doorColor, width: 2.2 * k)
            case (.door, .foldingDoor):
                // 折叠门：从门轴一侧往室内折
                let hingeLeft = (o.hinge ?? .left) == .left
                let left = w.leftDirection
                let center = (p0 + p1) * 0.5
                let hingeP = center + left * (hingeLeft ? o.width / 2 : -o.width / 2)
                let across = left * (hingeLeft ? -1.0 : 1.0)
                var pts: [CGPoint] = []
                for i in 0...4 {
                    let along = hingeP + across * (o.width * 0.5 * Double(i) / 4)
                    pts.append(pt(along - w.outward * (i % 2 == 1 ? o.width * 0.12 : 0)))
                }
                ctx.setStrokeColor(doorColor.cgColor)
                ctx.setLineWidth(1.5 * k)
                ctx.addLines(between: pts)
                ctx.strokePath()
            case (.door, _):
                // 平开门：门扇 + 开门弧线
                let hingeLeft = (o.hinge ?? .left) == .left
                let outward = o.opensOutward ?? false
                let left = w.leftDirection
                let center = (p0 + p1) * 0.5
                let face = outward ? w.outward * t : Vec2(0, 0)
                let hingeP = center + left * (hingeLeft ? o.width / 2 : -o.width / 2) + face
                let freeP = center - left * (hingeLeft ? o.width / 2 : -o.width / 2) + face
                let swing = outward ? w.outward : w.outward * -1
                let hinge = pt(hingeP), leafEnd = pt(hingeP + swing * o.width), closed = pt(freeP)
                ctx.setStrokeColor(doorColor.cgColor)
                ctx.setLineWidth(1.5 * k)
                ctx.move(to: hinge)
                ctx.addLine(to: leafEnd)
                ctx.strokePath()
                let a0 = atan2(leafEnd.y - hinge.y, leafEnd.x - hinge.x)
                let a1 = atan2(closed.y - hinge.y, closed.x - hinge.x)
                var delta = a1 - a0
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                let arc = CGMutablePath()
                arc.addRelativeArc(center: hinge, radius: o.width * s, startAngle: a0, delta: delta)
                ctx.addPath(arc)
                ctx.setLineWidth(1 * k)
                ctx.strokePath()
            case (.window, .slidingWindow):
                line(0, 1, at: 0, color: windowColor, width: 1 * k)
                line(0, 1, at: 1, color: windowColor, width: 1 * k)
                line(0, 0.55, at: 0.35, color: windowColor, width: 2 * k)
                line(0.45, 1, at: 0.65, color: windowColor, width: 2 * k)
            case (.window, .fixedWindow):
                line(0, 1, at: 0, color: windowColor, width: 1 * k)
                line(0, 1, at: 1, color: windowColor, width: 1 * k)
                line(0, 1, at: 0.5, color: windowColor, width: 2.4 * k)
            case (.window, _):
                for f in [0.0, 0.5, 1.0] { line(0, 1, at: f, color: windowColor, width: 1.2 * k) }
            case (.opening, _):
                ctx.saveGState()
                ctx.setLineDash(phase: 0, lengths: [3 * k, 3 * k])
                line(0, 1, at: 0.5, color: selected ? selectColor : .gray, width: 1 * k)
                ctx.restoreGState()
            }

            let mid = pt((p0 + p1) * 0.5)
            let inward = CGPoint(x: -w.outward.x, y: w.outward.y)
            let labelPos = CGPoint(x: mid.x + inward.x * 14 * k, y: mid.y + inward.y * 14 * k)
            let name = L10n.title(o)
            let label = o.kind == .window
                ? String(localized: "\(name) \(Fmt.mm(o.width)) 高\(Fmt.mm(o.height)) 离地\(Fmt.mm(o.sillHeight))")
                : "\(name) \(Fmt.mm(o.width))"
            text(label, at: labelPos, font: .systemFont(ofSize: 9 * k, weight: selected ? .bold : .regular),
                 color: o.kind == .door ? doorColor : windowColor,
                 angle: readableAngle(pt(p0), pt(p1)), background: UIColor.white.withAlphaComponent(0.8), ctx: ctx)
        }

        // 墙长尺寸线（标在墙外侧）
        let dimColor = UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1)
        for w in plan.walls {
            let o = CGPoint(x: w.outward.x, y: -w.outward.y)
            let gap = max(w.thickness * s, 3 * k) + 16 * k
            let a = pt(w.start), c = pt(w.end)
            let la = CGPoint(x: a.x + o.x * gap, y: a.y + o.y * gap)
            let lc = CGPoint(x: c.x + o.x * gap, y: c.y + o.y * gap)
            ctx.setStrokeColor(dimColor.cgColor)
            ctx.setLineWidth(0.8 * k)
            ctx.move(to: la)
            ctx.addLine(to: lc)
            for p in [la, lc] {
                ctx.move(to: CGPoint(x: p.x - o.x * 5 * k, y: p.y - o.y * 5 * k))
                ctx.addLine(to: CGPoint(x: p.x + o.x * 5 * k, y: p.y + o.y * 5 * k))
            }
            ctx.strokePath()
            // 短墙放不下完整标签：依次退化成「不带墙高」「只有长度」「小字号长度」，再短就不标数字
            let length = Fmt.mm(w.length)
            let measured = w.measuredLength.map { String(localized: "（实测 \(Fmt.mm($0))）") } ?? ""
            let height = plan.differingWallHeight(w).map { String(localized: " 高\(Fmt.mm($0))") } ?? ""
            let normal = UIFont.systemFont(ofSize: 11 * k, weight: .medium)
            let small = UIFont.systemFont(ofSize: 8 * k, weight: .medium)
            let room = hypot(lc.x - la.x, lc.y - la.y) + 12 * k
            let candidates: [(String, UIFont)] = [
                (length + measured + height, normal),
                (length + measured, normal),
                (length, normal),
                (length, small),
            ]
            if w.length >= 0.3,
               let (label, font) = candidates.first(where: { ($0.0 as NSString).size(withAttributes: [.font: $0.1]).width <= room })
                ?? (w.length >= 0.6 ? candidates.last : nil) {
                text(label, at: CGPoint(x: (la.x + lc.x) / 2, y: (la.y + lc.y) / 2), font: font,
                     color: dimColor, angle: readableAngle(la, lc), background: .white, ctx: ctx)
            }
        }

        // 房间名 + 面积
        for room in plan.rooms where room.floorPolygon.count >= 3 {
            let c = pt(Geo.centroid(room.floorPolygon))
            text(room.name, at: CGPoint(x: c.x, y: c.y - 9 * k), font: .systemFont(ofSize: 16 * k, weight: .semibold), color: .black, ctx: ctx)
            text(String(localized: "\(Fmt.area(room.area)) ㎡ · 层高 \(Fmt.mm(room.height))"), at: CGPoint(x: c.x, y: c.y + 11 * k),
                 font: .systemFont(ofSize: 10 * k), color: .darkGray, ctx: ctx)
        }

        // 标注
        for ann in plan.annotations {
            switch ann.kind {
            case .note:
                let p = pt(ann.position.xy)
                let r = 9 * k
                ctx.setFillColor(UIColor.systemBlue.cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                text("\(ann.number)", at: p, font: .systemFont(ofSize: 10 * k, weight: .bold), color: .white, ctx: ctx)
            case .measurement:
                guard let end = ann.endPosition else { continue }
                let a = pt(ann.position.xy), c = pt(end.xy)
                ctx.saveGState()
                ctx.setLineDash(phase: 0, lengths: [5 * k, 3 * k])
                ctx.setStrokeColor(UIColor.systemOrange.cgColor)
                ctx.setLineWidth(1.2 * k)
                ctx.move(to: a)
                ctx.addLine(to: c)
                ctx.strokePath()
                ctx.restoreGState()
                text(String(localized: "测 \(Fmt.mm(ann.distance ?? 0))"), at: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2),
                     font: .systemFont(ofSize: 10 * k, weight: .medium), color: .systemOrange,
                     angle: readableAngle(a, c), background: .white, ctx: ctx)
            }
        }

        // 1 米比例尺
        let barY = rect.maxY - 30 * k
        let barX = rect.maxX - margin - s
        ctx.setStrokeColor(UIColor.black.cgColor)
        ctx.setLineWidth(2 * k)
        ctx.move(to: CGPoint(x: barX, y: barY))
        ctx.addLine(to: CGPoint(x: barX + s, y: barY))
        ctx.strokePath()
        text("1 m", at: CGPoint(x: barX + s / 2, y: barY - 10 * k), font: .systemFont(ofSize: 10 * k), color: .black, ctx: ctx)
    }

    // MARK: - 文字

    private enum Align { case center, left }

    private static func readableAngle(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        var angle = atan2(b.y - a.y, b.x - a.x)
        if angle > .pi / 2 { angle -= .pi }
        if angle <= -.pi / 2 { angle += .pi }
        return angle
    }

    private static func text(_ s: String, at p: CGPoint, font: UIFont, color: UIColor, angle: CGFloat = 0,
                             align: Align = .center, background: UIColor? = nil, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        let x = align == .center ? -size.width / 2 : 0
        let r = CGRect(x: x, y: -size.height / 2, width: size.width, height: size.height)
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: r.insetBy(dx: -3, dy: -1), cornerRadius: 3).cgPath)
            ctx.fillPath()
        }
        (s as NSString).draw(in: r, withAttributes: attrs)
        ctx.restoreGState()
    }
}
