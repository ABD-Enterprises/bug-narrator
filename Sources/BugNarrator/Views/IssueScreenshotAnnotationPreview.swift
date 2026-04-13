import AppKit
import SwiftUI

struct IssueScreenshotAnnotationPreview: View {
    let screenshot: SessionScreenshot
    let annotations: [IssueScreenshotAnnotation]
    let onUpdate: (IssueScreenshotAnnotation) -> Void
    let onRemove: (IssueScreenshotAnnotation) -> Void

    @State private var activeAnnotationID: UUID?
    @State private var dragTranslation: CGSize = .zero

    private let maxPreviewHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = ScreenshotPreviewCache.shared.previewImage(for: screenshot.fileURL, maxPixelSize: 960) {
                GeometryReader { proxy in
                    let imageFrame = aspectFitFrame(for: image.size, in: proxy.size)

                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ForEach(annotations) { annotation in
                            annotationOverlay(
                                annotation: annotation,
                                imageFrame: imageFrame
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: maxPreviewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Annotated screenshot preview for \(screenshot.fileName)")
            } else {
                Text("Annotated preview unavailable for \(screenshot.fileName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(screenshot.fileName)
                    .font(.caption.weight(.semibold))

                Text(screenshot.timeLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func annotationOverlay(
        annotation: IssueScreenshotAnnotation,
        imageFrame: CGRect
    ) -> some View {
        let baseRect = displayRect(for: annotation, imageFrame: imageFrame)
        let isActive = activeAnnotationID == annotation.id
        let displayRect = isActive
            ? baseRect.offsetBy(dx: dragTranslation.width, dy: dragTranslation.height)
            : baseRect

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.95), lineWidth: isActive ? 3 : 2)
                )

            Button {
                onRemove(annotation)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white, .black.opacity(0.75))
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Remove annotation \(annotation.label ?? "highlight") from \(screenshot.fileName)")
        }
        .overlay(alignment: .topLeading) {
            if let label = annotation.label, !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .padding(8)
            }
        }
        .frame(width: displayRect.width, height: displayRect.height)
        .position(x: displayRect.midX, y: displayRect.midY)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    activeAnnotationID = annotation.id
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    activeAnnotationID = nil
                    dragTranslation = .zero

                    guard imageFrame.width > 0, imageFrame.height > 0 else {
                        return
                    }

                    var updatedAnnotation = annotation
                    updatedAnnotation.move(
                        x: value.translation.width / imageFrame.width,
                        y: value.translation.height / imageFrame.height
                    )
                    onUpdate(updatedAnnotation)
                }
        )
        .accessibilityLabel(annotation.label ?? "UI highlight")
        .accessibilityHint("Drag to reposition the highlighted region.")
    }

    private func displayRect(for annotation: IssueScreenshotAnnotation, imageFrame: CGRect) -> CGRect {
        let rect = annotation.normalizedRect
        return CGRect(
            x: imageFrame.origin.x + (rect.origin.x * imageFrame.width),
            y: imageFrame.origin.y + (rect.origin.y * imageFrame.height),
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func aspectFitFrame(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )
        return CGRect(origin: origin, size: fittedSize)
    }
}
