import SwiftUI

/// App 里的平面图：铺满视图，可以双指缩放；点门窗、点墙会回调
struct FloorPlanView: View {
    let plan: FloorPlanData
    let highlightRoomId: String?
    var selectedOpeningId: String?
    var selectedWallId: String?
    var selectedColumnId: String?
    var onTap: (PlanHit) -> Void = { _ in }

    private struct RenderKey: Equatable {
        var plan: FloorPlanData
        var highlight: String?
        var opening: String?
        var wall: String?
        var column: String?
        var size: CGSize
    }

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let scale = zoom * pinch
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Color.white
                    }
                }
                .frame(width: geo.size.width * scale, height: geo.size.height * scale)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let point = CGPoint(x: location.x / scale, y: location.y / scale)
                    onTap(FloorPlanRenderer.hitTest(plan, layout: FloorPlanRenderer.screenLayout(plan, size: geo.size), at: point))
                }
            }
            .gesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { zoom = min(max(zoom * $0, 1), 4) }
            )
            .task(id: RenderKey(plan: plan, highlight: highlightRoomId, opening: selectedOpeningId,
                                wall: selectedWallId, column: selectedColumnId, size: geo.size)) {
                guard geo.size.width > 0, geo.size.height > 0 else { return }
                // 按最大缩放倍数出图，放大后也清晰
                image = FloorPlanRenderer.screenImage(plan, size: geo.size, scale: displayScale * 2,
                                                      highlightRoomId: highlightRoomId,
                                                      selectedOpeningId: selectedOpeningId, selectedWallId: selectedWallId,
                                                      selectedColumnId: selectedColumnId)
            }
        }
        .background(Color.white)
    }
}
