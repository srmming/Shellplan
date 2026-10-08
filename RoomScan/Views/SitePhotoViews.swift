import SwiftUI

/// 现场照片墙：按房间分组，可以点开看大图、删掉拍坏的
struct SitePhotoGallery: View {
    let projectId: UUID
    let plan: FloorPlanData
    var onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var groups: [(title: String, photos: [FloorPlanData.SitePhoto])] {
        var result: [(String, [FloorPlanData.SitePhoto])] = plan.rooms.map { room in
            (room.name, plan.sitePhotos.filter { $0.roomId == room.id })
        }
        result.append(("其他", plan.sitePhotos.filter { p in p.roomId == nil || plan.room(p.roomId!) == nil }))
        return result.filter { !$0.1.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.sitePhotos.isEmpty {
                    ContentUnavailableView("还没有现场照片", systemImage: "photo.on.rectangle",
                                           description: Text("扫描时打开「自动拍照」，或者点「这里拍照」"))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(groups, id: \.title) { group in
                                Text("\(group.title) · \(group.photos.count) 张").font(.headline).padding(.horizontal)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                                    ForEach(group.photos) { photo in
                                        NavigationLink {
                                            SitePhotoViewer(projectId: projectId, photo: photo, plan: plan, onDelete: onDelete)
                                        } label: {
                                            PhotoThumb(projectId: projectId, path: photo.path)
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("现场照片 \(plan.sitePhotos.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct PhotoThumb: View {
    let projectId: UUID
    let path: String
    @EnvironmentObject private var store: ProjectStore
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: path) {
                let url = store.photoURL(projectId: projectId, relativePath: path)
                image = await Task.detached {
                    UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 240, height: 320))
                }.value
            }
    }
}

struct SitePhotoViewer: View {
    let projectId: UUID
    let photo: FloorPlanData.SitePhoto
    let plan: FloorPlanData
    var onDelete: (String) -> Void

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var info: String {
        var parts: [String] = []
        if let r = photo.roomId.flatMap({ plan.room($0) }) { parts.append(r.name) }
        if let w = photo.wallId { parts.append("拍的是墙 \(w)") }
        parts.append(photo.isAuto ? "自动拍摄" : "手动拍摄")
        parts.append("离地 \(Fmt.mm(photo.cameraPosition.z)) mm")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let image = UIImage(contentsOfFile: store.photoURL(projectId: projectId, relativePath: photo.path).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                ContentUnavailableView("照片文件不见了", systemImage: "photo")
            }
            Text(info)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
        .navigationTitle(photo.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("删除", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("删除这张照片？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                onDelete(photo.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }
}
