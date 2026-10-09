import Foundation
import UIKit

/// 打包给 AI 的导出包：白模 OBJ/USDA、尺寸平面图、scene.json、照片、Blender 重建脚本、AI 说明，最后压成 zip
enum ExportPackager {
    enum PackError: LocalizedError {
        case zipFailed
        var errorDescription: String? { String(localized: "压缩导出包失败") }
    }

    static func makePackage(project: Project, projectDir: URL) throws -> URL {
        let fm = FileManager.default
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        let folderName = "\(safeName(project.name))_\(df.string(from: Date()))"
        let base = fm.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? fm.removeItem(at: base)
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("photos"), withIntermediateDirectories: true)

        var plan = project.plan
        plan.meta.projectName = project.name
        plan.fixtures = []
        let wb = WhiteboxBuilder.build(plan)

        let (obj, mtl) = OBJExporter.export(plan, whitebox: wb)
        try obj.write(to: dir.appendingPathComponent("whitebox.obj"), atomically: true, encoding: .utf8)
        try mtl.write(to: dir.appendingPathComponent("whitebox.mtl"), atomically: true, encoding: .utf8)
        try GLBExporter.export(plan, whitebox: wb).write(to: dir.appendingPathComponent("whitebox.glb"))
        try USDAExporter.export(plan, whitebox: wb).write(to: dir.appendingPathComponent("whitebox.usda"), atomically: true, encoding: .utf8)
        try JSONCoding.encoder.encode(plan).write(to: dir.appendingPathComponent("scene.json"))
        try FloorPlanRenderer.image(plan, width: 3000).pngData()?.write(to: dir.appendingPathComponent("floorplan.png"))
        try FloorPlanRenderer.pdfData(plan).write(to: dir.appendingPathComponent("floorplan.pdf"))

        for rel in plan.annotations.flatMap(\.photos) + plan.sitePhotos.map(\.path) {
            let src = projectDir.appendingPathComponent(rel)
            let dst = dir.appendingPathComponent(rel)
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }

        // AI 生图素材：每个视角一组「现场照片 / 空房间白模图 / 深度图」
        let aiDir = dir.appendingPathComponent("ai_images", isDirectory: true)
        try fm.createDirectory(at: aiDir, withIntermediateDirectories: true)
        for shot in AIImageRenderer.shots(for: plan) {
            if let photo = shot.photo {
                let src = projectDir.appendingPathComponent(photo)
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: aiDir.appendingPathComponent("\(shot.id)_photo.jpg"))
                }
            }
            try AIImageRenderer.render(plan, shot: shot, depth: false)?.pngData()?
                .write(to: aiDir.appendingPathComponent("\(shot.id)_whitebox.png"))
            try AIImageRenderer.render(plan, shot: shot, depth: true)?.pngData()?
                .write(to: aiDir.appendingPathComponent("\(shot.id)_depth.png"))
        }

        let original = projectDir.appendingPathComponent("roomplan_original.usdz")
        if fm.fileExists(atPath: original.path) {
            try? fm.copyItem(at: original, to: dir.appendingPathComponent("roomplan_original.usdz"))
        }

        if let py = Bundle.main.url(forResource: "build_whitebox", withExtension: "py") {
            try? fm.copyItem(at: py, to: dir.appendingPathComponent("build_whitebox.py"))
        }
        try readme(plan).write(to: dir.appendingPathComponent("AI_README.md"), atomically: true, encoding: .utf8)

        return try zip(dir, name: folderName)
    }

    private static func zip(_ dir: URL, name: String) throws -> URL {
        let dest = dir.deletingLastPathComponent().appendingPathComponent("\(name).zip")
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: [.forUploading], error: &coordError) { tmp in
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: tmp, to: dest)
            } catch {
                copyError = error
            }
        }
        if let e = coordError { throw e }
        if let e = copyError { throw e }
        guard FileManager.default.fileExists(atPath: dest.path) else { throw PackError.zipFailed }
        return dest
    }

    private static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>| ")
        let cleaned = s.components(separatedBy: bad).filter { !$0.isEmpty }.joined(separator: "_")
        return cleaned.isEmpty ? "Shellplan" : cleaned
    }

    /// 给 AI 的说明：界面是中文时用中文模板，其他语言用英文模板
    static func readme(_ plan: FloorPlanData, chinese: Bool = L10n.isChinese) -> String {
        struct Words {
            var tableHeader, noText, photosLabel, noteLabel, measureLabel, noNotes, scanned, measured, noMeasured: String
        }
        let w = chinese
            ? Words(tableHeader: "| 房间 id | 名称 | 面积 ㎡ | 层高 mm | 墙 |", noText: "（无文字）", photosLabel: " 照片：",
                    noteLabel: "备注", measureLabel: "测距", noNotes: "- （没有标注）", scanned: "扫描", measured: "实测",
                    noMeasured: "- （没有填写实测值）")
            : Words(tableHeader: "| Room id | Name | Area m² | Height mm | Walls |", noText: "(no text)", photosLabel: " Photos: ",
                    noteLabel: "Note", measureLabel: "Measurement", noNotes: "- (no annotations)", scanned: "scanned",
                    measured: "measured", noMeasured: "- (no tape-measured values)")

        var rows = w.tableHeader + "\n|---|---|---|---|---|\n"
        for r in plan.rooms {
            let walls = plan.walls.filter { $0.roomIds.contains(r.id) }.map(\.id).joined(separator: ", ")
            rows += "| \(r.id) | \(r.name) | \(Fmt.area(r.area)) | \(Fmt.mm(r.height)) | \(walls) |\n"
        }

        var notes = ""
        for a in plan.annotations.sorted(by: { $0.number < $1.number }) {
            let pos = "(\(Fmt.mm(a.position.x)), \(Fmt.mm(a.position.y)), \(Fmt.mm(a.position.z)))"
            switch a.kind {
            case .note:
                let photos = a.photos.isEmpty ? "" : w.photosLabel + a.photos.joined(separator: ", ")
                notes += "- \(w.noteLabel) \(a.number) @ \(pos) mm: \(a.text.isEmpty ? w.noText : a.text)\(photos)\n"
            case .measurement:
                notes += "- \(w.measureLabel) \(a.number): \(Fmt.mm(a.distance ?? 0)) mm \(a.text)\n"
            }
        }
        if notes.isEmpty { notes = w.noNotes + "\n" }

        let measured = plan.walls.filter { $0.measuredLength != nil }
            .map { "- \($0.id): \(w.scanned) \(Fmt.mm($0.length)) mm, \(w.measured) \(Fmt.mm($0.measuredLength!)) mm" }
            .joined(separator: "\n")

        let template: String
        if let url = Bundle.main.url(forResource: chinese ? "AI_README" : "AI_README_en", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            template = s
        } else {
            template = "# {{PROJECT_NAME}}\n\n{{ROOM_TABLE}}\n\n{{ANNOTATIONS}}\n"
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return template
            .replacingOccurrences(of: "{{PROJECT_NAME}}", with: plan.meta.projectName)
            .replacingOccurrences(of: "{{DATE}}", with: df.string(from: plan.meta.createdAt))
            .replacingOccurrences(of: "{{TOTAL_AREA}}", with: Fmt.area(plan.totalArea))
            .replacingOccurrences(of: "{{ROOM_COUNT}}", with: "\(plan.rooms.count)")
            .replacingOccurrences(of: "{{ROOM_TABLE}}", with: rows)
            .replacingOccurrences(of: "{{ANNOTATIONS}}", with: notes)
            .replacingOccurrences(of: "{{MEASURED}}", with: measured.isEmpty ? w.noMeasured : measured)
    }
}
