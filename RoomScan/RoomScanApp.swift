import SwiftUI

@main
struct RoomScanApp: App {
    @StateObject private var store = ProjectStore()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-selftest-export") { SelfTest.runExport() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
                .preferredColorScheme(DemoMode.isActive ? .light : nil)
        }
    }
}

#if DEBUG
/// 调试用：命令行带 -selftest-export 启动时，把示例户型和手机上所有已保存的户型都导出一遍，结果写到 Documents/selftest.log
enum SelfTest {
    static func runExport() {
        Task.detached {
            var log: [String] = []
            func print(_ line: String) { log.append(line) }
            defer {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? log.joined(separator: "\n").write(to: docs.appendingPathComponent("selftest.log"), atomically: true, encoding: .utf8)
            }
            let store = ProjectStore()
            let now = Date()
            var projects = [Project(id: UUID(), name: "自检示例", createdAt: now, updatedAt: now, plan: SampleData.plan())]
            projects += store.projects
            for p in projects {
                do {
                    let zip = try ExportPackager.makePackage(project: p, projectDir: store.directory(for: p.id))
                    let size = (try? FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? 0
                    let files = (try? FileManager.default.contentsOfDirectory(atPath: zip.deletingPathExtension().path)) ?? []
                    print("SELFTEST OK \(p.name): \(size / 1024) KB, \(files.sorted().joined(separator: ","))")
                } catch {
                    print("SELFTEST FAIL \(p.name): \(error)")
                }
            }
            print("SELFTEST DONE")
        }
    }
}
#endif
