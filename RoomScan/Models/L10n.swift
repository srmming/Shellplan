import Foundation

/// 多处共用的本地化文字。界面里直接写 Text("…") 的文字由 SwiftUI 自动翻译；
/// 在代码里拼出来的文字（3D 标签、平面图、导出文件）要用 String(localized:)，统一放在这里或就地标注。
enum L10n {
    static func opening(_ kind: FloorPlanData.OpeningKind) -> String {
        switch kind {
        case .door: return String(localized: "门")
        case .window: return String(localized: "窗")
        case .opening: return String(localized: "洞口")
        }
    }

    static func style(_ style: FloorPlanData.OpeningStyle) -> String {
        switch style {
        case .swingDoor: return String(localized: "平开门")
        case .slidingDoor: return String(localized: "推拉门")
        case .foldingDoor: return String(localized: "折叠门")
        case .casementWindow: return String(localized: "平开窗")
        case .slidingWindow: return String(localized: "推拉窗")
        case .fixedWindow: return String(localized: "固定窗")
        case .awningWindow: return String(localized: "上悬窗")
        }
    }

    /// 门窗的显示名：标了样式就用样式名（推拉门），否则用类型名（门）
    static func title(_ o: FloorPlanData.Opening) -> String {
        o.style.map(style) ?? opening(o.kind)
    }

    /// 柱子的显示名，例如「柱 400×400」
    static func column(_ c: FloorPlanData.Column) -> String {
        String(localized: "柱 \(Fmt.mm(c.width))×\(Fmt.mm(c.depth))")
    }

    /// 当前界面语言是不是中文（简体或繁体）
    static var isChinese: Bool {
        (Bundle.main.preferredLocalizations.first ?? "zh-Hans").hasPrefix("zh")
    }
}

/// 房间名：扫描后给房间起名时的建议和常用列表
enum RoomName {
    static var living: String { String(localized: "客厅") }
    static var dining: String { String(localized: "餐厅") }
    static var masterBedroom: String { String(localized: "主卧") }
    static var secondBedroom: String { String(localized: "次卧") }
    static var kidsRoom: String { String(localized: "儿童房") }
    static var study: String { String(localized: "书房") }
    static var kitchen: String { String(localized: "厨房") }
    static var bathroom: String { String(localized: "卫生间") }
    static var masterBath: String { String(localized: "主卫") }
    static var balcony: String { String(localized: "阳台") }
    static var entrance: String { String(localized: "玄关") }
    static var hallway: String { String(localized: "走廊") }
    static var storage: String { String(localized: "储物间") }

    static func generic(_ n: Int) -> String { String(localized: "房间\(n)") }

    static var presets: [String] {
        [living, dining, masterBedroom, secondBedroom, kidsRoom, study, kitchen, bathroom, masterBath,
         balcony, entrance, hallway, storage]
    }
}

/// 示例户型和 RoomPlan 识别都会用到的设施名
enum FixtureName {
    static var toilet: String { String(localized: "马桶") }
    static var sink: String { String(localized: "水槽/洗手盆") }
}
