import SwiftUI

struct FloorPlanView: View {
    let plan: FloorPlanData
    let highlightRoomId: String?

    private struct RenderKey: Equatable {
        var plan: FloorPlanData
        var highlight: String?
    }

    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                if let image {
                    let w = geo.size.width * zoom * pinch
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: w, height: w * image.size.height / image.size.width)
                } else {
                    ProgressView().frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .gesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { zoom = min(max(zoom * $0, 1), 6) }
            )
        }
        .background(Color.white)
        .task(id: RenderKey(plan: plan, highlight: highlightRoomId)) {
            image = FloorPlanRenderer.image(plan, highlightRoomId: highlightRoomId, width: 2000)
        }
    }
}
