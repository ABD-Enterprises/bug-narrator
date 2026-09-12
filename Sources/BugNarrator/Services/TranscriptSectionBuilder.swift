import Foundation

enum TranscriptSectionBuilder {
    static func buildSections(
        transcript: String,
        segments: [TranscriptionSegment],
        markers: [SessionMarker],
        duration: TimeInterval
    ) -> [TranscriptSection] {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        if markers.isEmpty {
            return [
                TranscriptSection(
                    title: "Full Session",
                    startTime: 0,
                    endTime: duration,
                    text: transcript,
                    markerID: nil,
                    screenshotIDs: []
                )
            ]
        }

        if !segments.isEmpty {
            return buildSegmentBackedSections(
                transcript: transcript,
                segments: segments,
                markers: markers,
                duration: duration
            )
        }

        return buildCharacterBackedSections(
            transcript: transcript,
            markers: markers,
            duration: duration
        )
    }

    private static func buildSegmentBackedSections(
        transcript: String,
        segments: [TranscriptionSegment],
        markers: [SessionMarker],
        duration: TimeInterval
    ) -> [TranscriptSection] {
        let intervals = makeIntervals(markers: markers, duration: duration)
        let fallbackSections = buildCharacterBackedSections(
            transcript: transcript,
            markers: markers,
            duration: duration
        )

        return intervals.enumerated().map { index, interval in
            let sectionText = segments
                .filter { segment in
                    let midpoint = (segment.start + segment.end) / 2
                    if interval.isLast {
                        return midpoint >= interval.start && midpoint <= interval.end
                    }

                    return midpoint >= interval.start && midpoint < interval.end
                }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return TranscriptSection(
                title: interval.title,
                startTime: interval.start,
                endTime: interval.end,
                text: sectionText.isEmpty ? fallbackSections[index].text : sectionText,
                markerID: interval.marker?.id,
                screenshotIDs: interval.marker?.screenshotID.map { [$0] } ?? []
            )
        }
    }

    private static func buildCharacterBackedSections(
        transcript: String,
        markers: [SessionMarker],
        duration: TimeInterval
    ) -> [TranscriptSection] {
        let intervals = makeIntervals(markers: markers, duration: duration)
        let characters = Array(transcript)

        return intervals.enumerated().map { index, interval in
            let startFraction = duration > 0 ? interval.start / duration : 0
            let endFraction = duration > 0 ? interval.end / duration : 1
            let startIndex = max(Int(Double(characters.count) * startFraction), 0)
            let endIndex: Int

            if index == intervals.count - 1 {
                endIndex = characters.count
            } else {
                endIndex = min(max(Int(Double(characters.count) * endFraction), startIndex), characters.count)
            }

            let slice = characters[startIndex..<endIndex]
            let sectionText = String(slice).trimmingCharacters(in: .whitespacesAndNewlines)
            // Only a degenerate duration (every fraction collapses to 0) justifies
            // handing a section the whole transcript. With a real duration an
            // empty slice is a genuinely empty section — two markers pressed
            // 0.2 s apart used to put the entire transcript under the first one.
            let fallbackText = duration > 0 ? "" : transcript

            return TranscriptSection(
                title: interval.title,
                startTime: interval.start,
                endTime: interval.end,
                text: sectionText.isEmpty ? fallbackText : sectionText,
                markerID: interval.marker?.id,
                screenshotIDs: interval.marker?.screenshotID.map { [$0] } ?? []
            )
        }
    }

    private static func makeIntervals(markers: [SessionMarker], duration: TimeInterval) -> [SectionInterval] {
        var intervals: [SectionInterval] = []

        if let firstMarker = markers.first, firstMarker.elapsedTime > 0 {
            intervals.append(
                SectionInterval(
                    title: "Opening Notes",
                    start: 0,
                    end: firstMarker.elapsedTime,
                    marker: nil,
                    isLast: false
                )
            )
        }

        for (index, marker) in markers.enumerated() {
            let end = index + 1 < markers.count ? markers[index + 1].elapsedTime : duration
            intervals.append(
                SectionInterval(
                    title: marker.title,
                    start: marker.elapsedTime,
                    end: max(end, marker.elapsedTime),
                    marker: marker,
                    isLast: index == markers.count - 1
                )
            )
        }

        return intervals
    }
}

private struct SectionInterval {
    let title: String
    let start: TimeInterval
    let end: TimeInterval
    let marker: SessionMarker?
    let isLast: Bool
}
