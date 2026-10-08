import Foundation
import UIKit

/// 项目存在 Documents/Projects/<id>/ 下：project.json、photos/、roomplan_original.usdz。
/// Documents 在「文件」App 里可见。
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    private let fm = FileManager.default
    let root: URL

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent(DemoMode.isActive ? "DemoProjects" : "Projects", isDirectory: true)
        if DemoMode.isActive {
            try? fm.removeItem(at: root)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            DemoMode.projects().forEach(save)
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func photoURL(projectId: UUID, relativePath: String) -> URL {
        directory(for: projectId).appendingPathComponent(relativePath)
    }

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func load() {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")) else { return nil }
            return try? JSONCoding.decoder.decode(Project.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ project: Project) {
        let dir = directory(for: project.id)
        try? fm.createDirectory(at: dir.appendingPathComponent("photos"), withIntermediateDirectories: true)
        if let data = try? JSONCoding.encoder.encode(project) {
            try? data.write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        }
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ project: Project) {
        try? fm.removeItem(at: directory(for: project.id))
        projects.removeAll { $0.id == project.id }
    }

    @discardableResult
    func createProject(from output: ScanOutput) -> Project {
        let id = UUID()
        let dir = directory(for: id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let srcPhotos = output.workDir.appendingPathComponent("photos")
        if fm.fileExists(atPath: srcPhotos.path) {
            try? fm.moveItem(at: srcPhotos, to: dir.appendingPathComponent("photos"))
        }
        let srcUSDZ = output.workDir.appendingPathComponent("roomplan_original.usdz")
        if fm.fileExists(atPath: srcUSDZ.path) {
            try? fm.moveItem(at: srcUSDZ, to: dir.appendingPathComponent("roomplan_original.usdz"))
        }
        try? fm.removeItem(at: output.workDir)

        let now = Date()
        let project = Project(id: id, name: output.plan.meta.projectName, createdAt: now, updatedAt: now, plan: output.plan)
        save(project)
        return project
    }

    /// 存一张照片，返回相对路径（photos/xxx.jpg）
    func savePhoto(_ image: UIImage, projectId: UUID) throws -> String {
        let rel = "photos/IMG_\(UUID().uuidString.prefix(8)).jpg"
        let url = photoURL(projectId: projectId, relativePath: rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = image.downscaled(maxSide: 2048).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return rel
    }
}

extension UIImage {
    func downscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let ratio = maxSide / longest
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
