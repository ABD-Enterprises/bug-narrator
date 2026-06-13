import AppKit
import SwiftUI

extension TranscriptView {
    @ViewBuilder
    func screenshotsSection(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        if session.screenshots.isEmpty {
            emptyDetailState(
                title: "No screenshots yet",
                message: "Capture a screenshot during recording to review it here."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(session.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                    screenshotTimelineRow(screenshot, index: index, session: session, availableWidth: availableWidth)
                }
            }
        }
    }

    func screenshotTimelineRow(_ screenshot: SessionScreenshot, index: Int, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        let linkedMarker = screenshot.associatedMarkerID.flatMap { session.marker(with: $0) }

        return VStack(alignment: .leading, spacing: 10) {
            if availableWidth < 420 {
                VStack(alignment: .leading, spacing: 10) {
                    screenshotMetadataBlock(screenshot, index: index, linkedMarker: linkedMarker)

                    Button("Open Screenshot") {
                        appState.openScreenshot(screenshot)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(screenshotActionLabel(for: screenshot, index: index, action: "Open"))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    screenshotMetadataBlock(screenshot, index: index, linkedMarker: linkedMarker)

                    Spacer()

                    Button("Open Screenshot") {
                        appState.openScreenshot(screenshot)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(screenshotActionLabel(for: screenshot, index: index, action: "Open"))
                }
            }

            Button {
                appState.openScreenshot(screenshot)
            } label: {
                screenshotPreview(screenshot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(screenshotActionLabel(for: screenshot, index: index, action: "Open"))
            .accessibilityHint("Opens the saved screenshot file.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func screenshotMetadataBlock(_ screenshot: SessionScreenshot, index: Int, linkedMarker: SessionMarker?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Screenshot")
                    .font(.body.weight(.semibold))

                Text("\(index + 1)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 8) {
                metadataChip(label: screenshot.timeLabel, systemImage: "clock")

                if let linkedMarker {
                    metadataChip(label: linkedMarker.title, systemImage: "mappin.and.ellipse")
                }
            }
        }
    }

    @ViewBuilder
    func screenshotPreview(_ screenshot: SessionScreenshot) -> some View {
        if let image = ScreenshotPreviewCache.shared.previewImage(for: screenshot.fileURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 220, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.quaternary.opacity(0.5), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180)
                .overlay(alignment: .center) {
                    Text("[preview unavailable]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
        }
    }
}
