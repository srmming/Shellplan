import UIKit

/// 俯视尺寸平面图（单位 mm）。App 里的平面图页面、导出的 PNG / PDF 都用这一个绘制函数。
enum FloorPlanRenderer {
    static func image(_ plan: FloorPlanData, highlightRoomId: String? = nil, width: CGFloat = 2400) -> UIImage {
        let size = canvasSize(plan, width: width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(plan, in: ctx.cgContext, rect: CGRect(origin: .zero, size: size), highlightRoomId: highlightRoomId)
        }
    }

    /// A3 横向
    static func pdfData(_ plan: FloorPlanData) -> Data {
        let page = CGRect(x: 0, y: 0, width: 1191, height: 842)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            ctx.beginPage()
            draw(plan, in: ctx.cgContext, rect: page, highlightRoomId: nil)
        }
    }

    static func canvasSize(_ plan: FloorPlanData, width: CGFloat) -> CGSize {
        let b = plan.bounds
        let w = max(b.max.x - b.min.x, 1), h = max(b.max.y - b.min.y, 1)
        let aspect = min(max(h / w, 0.55), 1.6)
        return CGSize(width: width, height: (width * aspect + width * 0.1).rounded())
    }

    static func draw(_ plan: FloorPlanData, in ctx: CGContext, rect: CGRect, highlightRoomId: String?) {
        UIColor.white.setFill()
        ctx.fill(rect)

        let k = rect.width / 1000
        let titleH = 64 * k
        let margin = 80 * k
        let b = plan.bounds
        let bw = max(b.max.x - b.min.x, 0.5), bh = max(b.max.y - b.min.y, 0.5)
        let avail = CGRect(x: rect.minX + margin, y: rect.minY + titleH + margin,
                           width: rect.width - 2 * margin, height: rect.height - titleH - 2 * margin)
        let s = min(avail.width / bw, avail.height / bh)
        let ox = avail.minX + (avail.width - bw * s) / 2
        let oy = avail.minY + (avail.height - bh * s) / 2

        func pt(_ p: Vec2) -> CGPoint { CGPoint(x: ox + (p.x - b.min.x) * s, y: oy + (b.max.y - p.y) * s) }
        /// 平面向量 → 画布方向（画布 y 轴朝下）
        func cv(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: -v.y) }

        // 标题
        text(plan.meta.projectName, at: CGPoint(x: rect.minX + margin, y: rect.minY + 30 * k),
             font: .systemFont(ofSize: 24 * k, weight: .semibold), color: .black, align: .left, ctx: ctx)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let sub = "\(plan.rooms.count) 个房间 · 总面积 \(Fmt.area(plan.totalArea)) ㎡ · 尺寸单位 mm · \(df.string(from: plan.meta.createdAt))"
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
            ctx.setStrokeColor(wallColor)
            ctx.setLineWidth(max(w.thickness * s, 3 * k))
            ctx.setLineCap(.square)
            ctx.move(to: pt(w.start + off))
            ctx.addLine(to: pt(w.end + off))
            ctx.strokePath()
        }

        // 门窗
        for o in plan.openings {
            guard let w = plan.wall(o.wallId) else { continue }
            let d = w.direction
            let p0 = w.start + d * (o.centerOffset - o.width / 2)
            let p1 = w.start + d * (o.centerOffset + o.width / 2)
            let off = w.outward * (w.thickness / 2)
            let wallWidth = max(w.thickness * s, 3 * k)

            ctx.setLineCap(.butt)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(wallWidth + 2 * k)
            ctx.move(to: pt(p0 + off))
            ctx.addLine(to: pt(p1 + off))
            ctx.strokePath()

            switch o.kind {
            case .door:
                let green = UIColor(red: 0.18, green: 0.55, blue: 0.34, alpha: 1)
                let hinge = pt(p0), leafEnd = pt(p0 - w.outward * o.width), closed = pt(p1)
                ctx.setStrokeColor(green.cgColor)
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
            case .window:
                ctx.setStrokeColor(UIColor.systemBlue.cgColor)
                ctx.setLineWidth(1.2 * k)
                for f in [0.0, 0.5, 1.0] {
                    let shift = w.outward * (w.thickness * f)
                    ctx.move(to: pt(p0 + shift))
                    ctx.addLine(to: pt(p1 + shift))
                }
                ctx.strokePath()
            case .opening:
                ctx.saveGState()
                ctx.setLineDash(phase: 0, lengths: [3 * k, 3 * k])
                ctx.setStrokeColor(UIColor.gray.cgColor)
                ctx.setLineWidth(1 * k)
                ctx.move(to: pt(p0 + off))
                ctx.addLine(to: pt(p1 + off))
                ctx.strokePath()
                ctx.restoreGState()
            }

            let mid = pt((p0 + p1) * 0.5)
            let inward = cv(w.outward * -1)
            let labelPos = CGPoint(x: mid.x + inward.x * 14 * k, y: mid.y + inward.y * 14 * k)
            let label: String
            switch o.kind {
            case .door: label = "门 \(Fmt.mm(o.width))"
            case .window: label = "窗 \(Fmt.mm(o.width)) 高\(Fmt.mm(o.height)) 离地\(Fmt.mm(o.sillHeight))"
            case .opening: label = "洞 \(Fmt.mm(o.width))"
            }
            text(label, at: labelPos, font: .systemFont(ofSize: 9 * k), color: o.kind == .door ? .systemGreen : .systemBlue,
                 angle: readableAngle(pt(p0), pt(p1)), background: UIColor.white.withAlphaComponent(0.8), ctx: ctx)
        }

        // 墙长尺寸线（标在墙外侧）
        let dimColor = UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1)
        for w in plan.walls {
            let o = cv(w.outward)
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
            let measured = w.measuredLength.map { "（实测 \(Fmt.mm($0))）" } ?? ""
            let height = plan.differingWallHeight(w).map { " 高\(Fmt.mm($0))" } ?? ""
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
            text("\(Fmt.area(room.area)) ㎡ · 层高 \(Fmt.mm(room.height))", at: CGPoint(x: c.x, y: c.y + 11 * k),
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
                text("测 \(Fmt.mm(ann.distance ?? 0))", at: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2),
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
