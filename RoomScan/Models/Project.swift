import Foundation
import UIKit

struct Project: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var plan: FloorPlanData

    var photoCount: Int { Set(plan.annotations.flatMap(\.photos) + plan.sitePhotos.map(\.path)).count }
}

/// 扫描结束时交给 ProjectStore 的结果。workDir 里有 photos/ 和 roomplan_original.usdz（如果有）
struct ScanOutput {
    var plan: FloorPlanData
    var workDir: URL
}

enum DeviceInfo {
    static var model: String {
        var info = utsname()
        uname(&info)
        let machine = Mirror(reflecting: info.machine).children.reduce(into: "") { acc, el in
            guard let v = el.value as? Int8, v != 0 else { return }
            acc.append(Character(UnicodeScalar(UInt8(v))))
        }
        return "\(machine) / iOS \(UIDevice.current.systemVersion)"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
