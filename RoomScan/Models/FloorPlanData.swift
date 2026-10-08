import Foundation

/// 二维点 / 向量（单位：米）
struct Vec2: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }

    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Vec2 {
        let l = length
        return l > 0 ? Vec2(x / l, y / l) : Vec2(0, 0)
    }
    /// 逆时针旋转 90° 得到的法线
    var perpendicular: Vec2 { Vec2(-y, x) }
    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
}

/// 三维点 / 向量（单位：米，Z 轴朝上，地面 z = 0）
struct Vec3: Codable, Hashable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }

    var length: Double { (x * x + y * y + z * z).squareRoot() }
    var xy: Vec2 { Vec2(x, y) }
}

/// 白模和尺寸图的唯一数据源。导出的 scene.json 就是它本身，所以字段命名以「AI 好读」为准。
struct FloorPlanData: Codable, Equatable {
    var schemaVersion: Int
    var meta: Meta
    var rooms: [Room]
    var walls: [Wall]
    var openings: [Opening]
    var fixtures: [Fixture]
    var annotations: [Annotation]
    /// 现场照片（扫描时自动拍的 + 手动拍的），带相机位姿
    var sitePhotos: [SitePhoto] = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion, meta, rooms, walls, openings, fixtures, annotations, sitePhotos
    }

    struct SitePhoto: Codable, Identifiable, Hashable {
        var id: String
        /// 相对导出包根目录的路径，例如 photos/AUTO_xxx.jpg
        var path: String
        var roomId: String?
        /// 照片主要拍到的墙
        var wallId: String?
        var cameraPosition: Vec3
        /// 镜头朝向（单位向量）
        var cameraDirection: Vec3
        /// 竖拍画面的「上」方向（单位向量）
        var cameraUp: Vec3
        /// 竖拍画面的垂直视角（度）
        var verticalFov: Double
        /// 画面中心对准的点
        var target: Vec3?
        var isAuto: Bool
        var createdAt: Date
    }

    struct Meta: Codable, Equatable {
        var projectName: String
        var createdAt: Date
        var device: String
        var appVersion: String
        var units: String
        var coordinateSystem: String
        var notes: [String]

        static func make(projectName: String) -> Meta {
            Meta(
                projectName: projectName,
                createdAt: Date(),
                device: DeviceInfo.model,
                appVersion: DeviceInfo.appVersion,
                units: "meters",
                coordinateSystem: "右手坐标系，Z 轴朝上（与 Blender 一致），地面 z = 0",
                notes: [
                    "墙线 start/end 是房间内侧墙面的位置，墙厚 thickness 向 outward 方向挤出",
                    "门窗 centerOffset 是洞口中心到墙 start 点的距离",
                    "measuredLength 是用户用卷尺实测的墙长，有值时优先使用",
                    "isCurved 为 true 的墙是弧形墙，这里近似成直线",
                    "sitePhotos 是现场照片，cameraPosition/cameraDirection/cameraUp/verticalFov 可以还原拍摄相机",
                ]
            )
        }
    }

    struct Room: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        /// RoomPlan 识别的类型：livingRoom / bedroom / kitchen / bathroom / diningRoom / unidentified
        var category: String
        /// 地面轮廓（逆时针）
        var floorPolygon: [Vec2]
        var height: Double
        var area: Double
    }

    struct Wall: Codable, Identifiable, Hashable {
        var id: String
        /// 墙所属的房间（两个房间之间的共用墙会有两个）
        var roomIds: [String]
        var start: Vec2
        var end: Vec2
        var length: Double
        var height: Double
        var thickness: Double
        /// 指向房间外侧的单位法线
        var outward: Vec2
        var measuredLength: Double?
        var isCurved: Bool

        var direction: Vec2 { (end - start).normalized }
        var midpoint: Vec2 { (start + end) * 0.5 }
    }

    enum OpeningKind: String, Codable {
        case door, window, opening
    }

    struct Opening: Codable, Identifiable, Hashable {
        var id: String
        var kind: OpeningKind
        var wallId: String
        var centerOffset: Double
        var width: Double
        var height: Double
        var sillHeight: Double
        var isOpen: Bool?
    }

    /// 固定设施（马桶、灶台等），决定水电位，作为参考层
    struct Fixture: Codable, Identifiable, Hashable {
        var id: String
        var category: String
        var name: String
        var roomId: String?
        var center: Vec3
        /// x = 宽，y = 深，z = 高
        var size: Vec3
        /// 绕 Z 轴的旋转（弧度）
        var yaw: Double
    }

    enum AnnotationKind: String, Codable {
        case note, measurement
    }

    struct Annotation: Codable, Identifiable, Hashable {
        var id: String
        var number: Int
        var kind: AnnotationKind
        var text: String
        var position: Vec3
        var endPosition: Vec3?
        var distance: Double?
        /// 相对导出包根目录的路径，例如 photos/abc.jpg
        var photos: [String]
        var cameraPosition: Vec3?
        var cameraDirection: Vec3?
        var createdAt: Date
    }
}

extension FloorPlanData {
    /// 旧版本保存的项目没有 sitePhotos 字段，解码时补空
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        meta = try c.decode(Meta.self, forKey: .meta)
        rooms = try c.decode([Room].self, forKey: .rooms)
        walls = try c.decode([Wall].self, forKey: .walls)
        openings = try c.decode([Opening].self, forKey: .openings)
        fixtures = try c.decode([Fixture].self, forKey: .fixtures)
        annotations = try c.decode([Annotation].self, forKey: .annotations)
        sitePhotos = try c.decodeIfPresent([SitePhoto].self, forKey: .sitePhotos) ?? []
    }

    func wall(_ id: String) -> Wall? { walls.first { $0.id == id } }
    func room(_ id: String) -> Room? { rooms.first { $0.id == id } }
    func openings(on wallId: String) -> [Opening] { openings.filter { $0.wallId == wallId } }

    /// 墙高和所在房间层高差 3cm 以上时返回墙高（通常是梁下或吊顶下的墙）
    func differingWallHeight(_ wall: Wall) -> Double? {
        guard let roomHeight = wall.roomIds.compactMap({ room($0)?.height }).max(),
              abs(wall.height - roomHeight) > 0.03 else { return nil }
        return wall.height
    }

    var totalArea: Double { rooms.reduce(0) { $0 + $1.area } }
    var maxHeight: Double { rooms.map(\.height).max() ?? walls.map(\.height).max() ?? 0 }
    var nextAnnotationNumber: Int { (annotations.map(\.number).max() ?? 0) + 1 }

    var bounds: (min: Vec2, max: Vec2) {
        var pts = walls.flatMap { [$0.start, $0.end] }
        pts += rooms.flatMap(\.floorPolygon)
        guard let first = pts.first else { return (Vec2(0, 0), Vec2(1, 1)) }
        var lo = first, hi = first
        for p in pts {
            lo = Vec2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo, hi)
    }

    /// 重新计算面积、墙长和墙的外法线。几何数据变动后都要调用。
    mutating func recomputeDerived() {
        for i in rooms.indices {
            rooms[i].floorPolygon = Geo.ensureCCW(rooms[i].floorPolygon)
            rooms[i].area = Geo.polygonArea(rooms[i].floorPolygon)
        }
        for i in walls.indices {
            var w = walls[i]
            w.length = (w.end - w.start).length
            let n = w.direction.perpendicular
            if let room = rooms.first(where: { w.roomIds.contains($0.id) }) {
                let c = Geo.centroid(room.floorPolygon)
                w.outward = (c - w.midpoint).dot(n) > 0 ? n * -1 : n
            } else {
                w.outward = n
            }
            walls[i] = w
        }
    }
}

enum Fmt {
    static func mm(_ meters: Double) -> String { String(Int((meters * 1000).rounded())) }
    static func area(_ a: Double) -> String { String(format: "%.1f", a) }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
