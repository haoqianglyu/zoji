import ImageIO
import SwiftUI
import UIKit

struct AvatarCropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum AvatarImageProcessor {
    /// Decode a bounded image and apply EXIF rotation/mirroring before editing.
    static func prepare(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Use the same image-space rectangle as the preview. Persist a square so
    /// every existing circular avatar displays exactly the selected composition.
    static func crop(_ image: UIImage, to rect: CGRect) -> Data? {
        guard rect.width.isFinite, rect.width > 0,
              rect.height.isFinite, abs(rect.width - rect.height) < 1,
              rect.minX.isFinite, rect.minY.isFinite,
              image.size.width > 0, image.size.height > 0
        else { return nil }

        let side = min(rect.width, image.size.width, image.size.height)
        let boundedRect = CGRect(
            x: min(max(0, rect.minX), image.size.width - side),
            y: min(max(0, rect.minY), image.size.height - side),
            width: side,
            height: side
        )
        let outputSide = max(1, min(1_024, floor(side * image.scale)))
        let outputSize = CGSize(width: outputSide, height: outputSide)
        let scale = outputSide / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: outputSize))
            image.draw(in: CGRect(
                x: -boundedRect.minX * scale,
                y: -boundedRect.minY * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
        return result.jpegData(compressionQuality: 0.85)
    }
}

struct AvatarCropView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorTheme) private var theme
    @State private var cropView: AvatarCropScrollView
    @State private var zoom: CGFloat = 1
    @State private var showsCropError = false

    let onConfirm: (Data) -> Void

    init(image: UIImage, onConfirm: @escaping (Data) -> Void) {
        _cropView = State(initialValue: AvatarCropScrollView(image: image))
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Text("拖动照片调整位置，双指缩放")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        AvatarCropCanvas(cropView: cropView) { zoom = $0 }
                            .frame(width: cropSide(in: geometry), height: cropSide(in: geometry))
                            .overlay {
                                GeometryReader { preview in
                                    Path { path in
                                        let rect = CGRect(origin: .zero, size: preview.size)
                                        path.addRect(rect)
                                        path.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
                                    }
                                    .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                                }
                                .allowsHitTesting(false)
                                Circle()
                                    .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("头像裁剪区域")
                            .accessibilityHint("拖动照片调整位置，双指缩放")

                        VStack(spacing: 12) {
                            HStack {
                                Text("缩放")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(Double(zoom).formatted(.number.precision(.fractionLength(1))) + "×")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 16) {
                                Image(systemName: "minus.magnifyingglass")
                                    .accessibilityHidden(true)
                                Slider(value: Binding(
                                    get: { zoom },
                                    set: {
                                        zoom = $0
                                        cropView.setRelativeZoom($0)
                                    }
                                ), in: 1...AvatarCropScrollView.maximumRelativeZoom)
                                .accessibilityLabel("缩放")
                                Image(systemName: "plus.magnifyingglass")
                                    .accessibilityHidden(true)
                            }
                            Button("重置") { cropView.resetCrop() }
                                .padding(.vertical, 8)
                        }
                        .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .frame(minHeight: geometry.size.height)
                }
            }
            .background(theme.background)
            .navigationTitle("裁剪头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用头像") {
                        guard let data = cropView.croppedData() else {
                            showsCropError = true
                            return
                        }
                        onConfirm(data)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("无法裁剪这张照片，请重试。", isPresented: $showsCropError) {
                Button("知道了", role: .cancel) { }
            }
        }
        .tint(theme.accent)
    }

    private func cropSide(in geometry: GeometryProxy) -> CGFloat {
        min(420, max(1, geometry.size.width - 48), max(180, geometry.size.height - 240))
    }
}

private struct AvatarCropCanvas: UIViewRepresentable {
    let cropView: AvatarCropScrollView
    let onZoomChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> AvatarCropScrollView {
        cropView.onZoomChange = onZoomChange
        return cropView
    }

    func updateUIView(_ uiView: AvatarCropScrollView, context: Context) {
        uiView.onZoomChange = onZoomChange
    }

    static func dismantleUIView(_ uiView: AvatarCropScrollView, coordinator: ()) {
        uiView.onZoomChange = nil
    }
}

/// A square viewport keeps UIKit's pan/pinch limits aligned with the crop.
final class AvatarCropScrollView: UIScrollView, UIScrollViewDelegate {
    static let maximumRelativeZoom: CGFloat = 5
    var onZoomChange: ((CGFloat) -> Void)?
    private let imageView: UIImageView
    private var previousViewportSize = CGSize.zero
    private var isConfiguring = false

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(imageView)
        delegate = self
        backgroundColor = .white
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = false
        bouncesZoom = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0,
              bounds.size != previousViewportSize else { return }

        // Preserve the selected image center and relative zoom on size changes.
        let center = previousViewportSize == .zero
            ? CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
            : CGPoint(x: (contentOffset.x + previousViewportSize.width / 2) / zoomScale,
                      y: (contentOffset.y + previousViewportSize.height / 2) / zoomScale)
        let relativeZoom = previousViewportSize == .zero ? 1 : zoomScale / minimumZoomScale
        previousViewportSize = bounds.size
        isConfiguring = true
        minimumZoomScale = min(minimumZoomScale, bounds.width / imageView.bounds.width,
                               bounds.height / imageView.bounds.height)
        maximumZoomScale = max(maximumZoomScale, relativeZoom)
        setZoomScale(1, animated: false)
        imageView.frame = CGRect(origin: .zero, size: imageView.bounds.size)
        contentSize = imageView.bounds.size
        let minimum = max(bounds.width / imageView.bounds.width, bounds.height / imageView.bounds.height)
        maximumZoomScale = minimum * Self.maximumRelativeZoom
        minimumZoomScale = minimum
        setZoomScale(minimum * relativeZoom, animated: false)
        centerImage(at: center)
        isConfiguring = false
        publishZoom()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if !isConfiguring { publishZoom() }
    }

    func setRelativeZoom(_ value: CGFloat) {
        guard previousViewportSize != .zero else { return }
        let center = CGPoint(x: (contentOffset.x + bounds.width / 2) / zoomScale,
                             y: (contentOffset.y + bounds.height / 2) / zoomScale)
        setZoomScale(min(max(value, 1), Self.maximumRelativeZoom) * minimumZoomScale, animated: false)
        centerImage(at: center)
    }

    func resetCrop() {
        setZoomScale(minimumZoomScale, animated: false)
        centerImage(at: CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY))
        publishZoom()
    }

    func croppedData() -> Data? {
        guard previousViewportSize != .zero, let image = imageView.image else { return nil }
        return AvatarImageProcessor.crop(image, to: CGRect(
            x: contentOffset.x / zoomScale,
            y: contentOffset.y / zoomScale,
            width: bounds.width / zoomScale,
            height: bounds.height / zoomScale
        ))
    }

    private func centerImage(at center: CGPoint) {
        contentOffset = CGPoint(
            x: min(max(0, center.x * zoomScale - bounds.width / 2), max(0, contentSize.width - bounds.width)),
            y: min(max(0, center.y * zoomScale - bounds.height / 2), max(0, contentSize.height - bounds.height))
        )
    }

    private func publishZoom() {
        // Layout can run during a SwiftUI update; publish on the next main turn.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onZoomChange?(self.zoomScale / self.minimumZoomScale)
        }
    }
}
