import Foundation

/// 截图用的演示模式（只在 Debug 版本生效）：
/// 启动参数 `-demo home|model|plan|note|export`，使用单独的 DemoProjects 目录，不会碰到真实的扫描数据。
enum DemoMode {
    static var screen: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo"), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    static var isActive: Bool { screen != nil }

    /// 演示数据：一套完整示例户型，再加两套只含部分房间的
    static func projects() -> [Project] {
        let full = SampleData.plan()
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        func subset(_ roomIds: Set<String>, name: String) -> FloorPlanData {
            var p = full
            p.meta.projectName = name
            p.rooms = p.rooms.filter { roomIds.contains($0.id) }
            p.walls = p.walls.filter { !Set($0.roomIds).isDisjoint(with: roomIds) }
            let wallIds = Set(p.walls.map(\.id))
            p.openings = p.openings.filter { wallIds.contains($0.wallId) }
            p.fixtures = p.fixtures.filter { $0.roomId.map(roomIds.contains) ?? false }
            p.annotations = []
            return p
        }
        let homeName = String(localized: "我家")
        let studioName = String(localized: "工作室")
        let bathName = String(localized: "爸妈家卫生间")
        var home = full
        home.meta.projectName = homeName
        return [
            Project(id: UUID(), name: homeName, createdAt: base, updatedAt: base.addingTimeInterval(3 * 86_400), plan: home),
            Project(id: UUID(), name: studioName, createdAt: base, updatedAt: base.addingTimeInterval(2 * 86_400),
                    plan: subset(["R1"], name: studioName)),
            Project(id: UUID(), name: bathName, createdAt: base, updatedAt: base.addingTimeInterval(86_400),
                    plan: subset(["R3"], name: bathName)),
        ]
    }
}
