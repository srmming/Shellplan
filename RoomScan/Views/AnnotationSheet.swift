import PhotosUI
import SwiftUI

struct AnnotationSheet: View {
    let projectId: UUID
    @State var annotation: FloorPlanData.Annotation
    let isNew: Bool
    var onSave: (FloorPlanData.Annotation, [UIImage]) -> Void
    var onDelete: () -> Void

    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var newImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    init(projectId: UUID, annotation: FloorPlanData.Annotation, isNew: Bool,
         onSave: @escaping (FloorPlanData.Annotation, [UIImage]) -> Void, onDelete: @escaping () -> Void) {
        self.projectId = projectId
        _annotation = State(initialValue: annotation)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                if annotation.kind == .measurement, let d = annotation.distance {
                    Section("测距") {
                        LabeledContent("距离", value: "\(Fmt.mm(d)) mm")
                    }
                }

                Section("备注") {
                    TextField(annotation.kind == .note ? String(localized: "例如：这面墙做电视柜，留 3 个插座") : String(localized: "这段距离是量什么的（可不填）"),
                              text: $annotation.text, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("照片") {
                    if !annotation.photos.isEmpty || !newImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(annotation.photos, id: \.self) { rel in
                                    thumbnail(UIImage(contentsOfFile: store.photoURL(projectId: projectId, relativePath: rel).path)) {
                                        annotation.photos.removeAll { $0 == rel }
                                    }
                                }
                                ForEach(newImages.indices, id: \.self) { i in
                                    thumbnail(newImages[i]) { newImages.remove(at: i) }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    HStack {
                        PhotosPicker(selection: $pickerItems, matching: .images) {
                            Label("从相册选", systemImage: "photo.on.rectangle")
                        }
                        Spacer()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Label("拍照", systemImage: "camera")
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }

                Section {
                    let p = annotation.position
                    LabeledContent("位置", value: "x \(Fmt.mm(p.x))  y \(Fmt.mm(p.y))  离地 \(Fmt.mm(p.z))")
                } footer: {
                    Text("单位 mm，地面高度为 0。导出时这些会一起交给 AI。")
                }

                if !isNew {
                    Section {
                        Button("删除这条标注", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "新备注") : (annotation.kind == .note ? String(localized: "备注 \(annotation.number)") : String(localized: "测距 \(annotation.number)")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(annotation, newImages)
                        dismiss()
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                            newImages.append(img)
                        }
                    }
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { newImages.append($0) }
                    .ignoresSafeArea()
            }
        }
    }

    private func thumbnail(_ image: UIImage?, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.borderless)
            .padding(4)
            .accessibilityLabel("移除照片")
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
