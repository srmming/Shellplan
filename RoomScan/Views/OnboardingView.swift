import RoomPlan
import SwiftUI

/// 首次打开时的使用说明，之后可以从首页右上角菜单再次打开
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0

    private struct Page {
        var icon: String
        var title: LocalizedStringKey
        var text: LocalizedStringKey
    }

    private let pages = [
        Page(icon: "viewfinder", title: "一间一间地扫",
             text: "拿着手机慢慢走一圈，对准墙角、门和窗。扫完一个房间给它起个名字，再去扫下一个，最后自动拼成全屋。"),
        Page(icon: "camera.aperture", title: "停一下就自动拍照",
             text: "扫描时手机拿稳就会自动拍照，并记下拍摄的位置和朝向。想拍清楚的细节，点「这里拍照」。"),
        Page(icon: "ruler", title: "白模和尺寸自动标好",
             text: "墙长、层高、门窗尺寸都会标出来。可以测距、加备注和照片；用卷尺量过的墙，可以填上实测值。"),
        Page(icon: "square.and.arrow.up", title: "一键导出给 AI",
             text: "打包白模（OBJ / USD）、尺寸平面图、照片和 Blender 重建脚本，发到电脑上交给 AI 做室内设计。"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: pages[i].icon)
                            .font(.system(size: 64, weight: .regular))
                            .foregroundStyle(Color.accentColor)
                            .frame(height: 90)
                        Text(pages[i].title)
                            .font(.title2.bold())
                        Text(pages[i].text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                if !RoomCaptureSession.isSupported {
                    Text("这台设备没有 LiDAR，不能扫描，但可以加载示例户型看看效果。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page < pages.count - 1 ? String(localized: "下一步") : String(localized: "开始使用"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if page < pages.count - 1 {
                    Button("跳过") { onDone() }
                        .font(.subheadline)
                }
            }
            .padding()
        }
    }
}
