//
//  SplitTimelineView.swift
//  VideoEditorKit
//

import SwiftUI

/// CapCut / VN style split timeline.
///
/// - Fixed centre playhead; the timeline scrolls under it (scrub by dragging).
/// - Pinch or use the zoom buttons to change the time scale.
/// - Thumbnails strip with a time ruler, segment outlines, dimmed deleted parts.
/// - Draggable split handles between parts.
/// - Bottom action bar that enables only the actions valid at the playhead.
struct SplitTimelineView: View {

    // MARK: - States

    @State private var pixelsPerSecond: CGFloat = Constants.defaultPixelsPerSecond
    @State private var pinchStartPixelsPerSecond: CGFloat?
    @State private var scrollPosition = ScrollPosition()
    @State private var isScrubbing = false
    @State private var draggedSplit: DraggedSplit?
    @State private var scrubTime = 0.0

    // MARK: - Public Properties

    /// Playhead position in timeline seconds, owned by the player.
    let currentTime: Double
    let video: Video
    let splitRevision: Int
    let availability: EditorViewModel.SplitActionAvailability
    let onSplit: () -> Void
    let onDelete: () -> Void
    let onRestorePart: () -> Void
    let onRestoreAll: () -> Void
    let onJoin: () -> Void
    let onMoveSplit: (_ point: Double, _ newSourceTime: Double) -> Void
    let onScrubBegan: () -> Void
    let onScrubChanged: (_ time: Double) -> Void
    let onScrubEnded: (_ time: Double) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            header
            timeline

            if !video.hasSplitEdits {
                Text(VideoEditorStrings.splitHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            actionBar
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.impact(weight: .medium), trigger: splitRevision)
    }

    // MARK: - Private Properties

    private enum Constants {
        static let defaultPixelsPerSecond: CGFloat = 60
        static let minimumPixelsPerSecond: CGFloat = 16
        static let maximumPixelsPerSecond: CGFloat = 320
        static let zoomStep: CGFloat = 1.4
        static let trackHeight: CGFloat = 56
        static let rulerHeight: CGFloat = 18
        static let handleHitWidth: CGFloat = 28
        static let trackSpace = "split-track"
    }

    private struct DraggedSplit: Equatable {
        let point: Double
        let proposedTime: Double
    }

    private var rate: Double {
        Double(max(video.rate, 0.01))
    }

    private var trackWidth: CGFloat {
        max(CGFloat(video.timelineDuration) * pixelsPerSecond, 1)
    }

    private var segmentStates: [VideoSplitEditor.SegmentState] {
        VideoSplitEditor.segmentStates(
            in: video.rangeDuration,
            splitPoints: video.splitPoints,
            removedRanges: video.removedRanges
        )
    }

    private var interiorSplitPoints: [Double] {
        segmentStates.dropFirst().map(\.range.lowerBound)
    }

    private var selectedRange: ClosedRange<Double>? {
        guard segmentStates.count > 1 else { return nil }

        let sourceTime = PlaybackTimeMapping.sourceTime(
            forTimelineTime: currentTime,
            rate: video.rate,
            originalDuration: video.originalDuration
        )

        return VideoSplitEditor.segment(
            containing: sourceTime,
            in: video.rangeDuration,
            splitPoints: video.splitPoints
        )
    }

    private var rulerStep: Double {
        let candidates: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60]
        return candidates.first { CGFloat($0) * pixelsPerSecond >= 56 } ?? 60
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchStartPixelsPerSecond ?? pixelsPerSecond
                pinchStartPixelsPerSecond = base
                pixelsPerSecond = clampedScale(base * value.magnification)
            }
            .onEnded { _ in
                pinchStartPixelsPerSecond = nil
            }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("\(Self.format(currentTime)) / \(Self.format(video.totalDuration))")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Spacer()

            Button {
                withAnimation(.snappy) {
                    pixelsPerSecond = clampedScale(pixelsPerSecond / Constants.zoomStep)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .accessibilityLabel(VideoEditorStrings.timelineZoomOut)

            Button {
                withAnimation(.snappy) {
                    pixelsPerSecond = clampedScale(pixelsPerSecond * Constants.zoomStep)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .accessibilityLabel(VideoEditorStrings.timelineZoomIn)
        }
        .font(.body)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    private var timeline: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 4) {
                    ruler()
                    trackView
                }
                .padding(.horizontal, proxy.size.width / 2)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offset in
                guard isScrubbing else { return }
                let time = time(forOffset: offset)
                scrubTime = time
                onScrubChanged(time)
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                switch (oldPhase.isScrolling, newPhase.isScrolling) {
                case (false, true):
                    isScrubbing = true
                    scrubTime = currentTime
                    onScrubBegan()
                case (true, false):
                    isScrubbing = false
                    onScrubEnded(scrubTime)
                default:
                    break
                }
            }
            .onChange(of: currentTime) { _, newValue in
                guard !isScrubbing else { return }
                syncScroll(to: newValue)
            }
            .onChange(of: pixelsPerSecond) { _, _ in
                syncScroll(to: currentTime)
            }
            .onAppear {
                syncScroll(to: currentTime)
            }
            .simultaneousGesture(magnifyGesture)
            .overlay { playhead }
        }
        .frame(height: Constants.trackHeight + Constants.rulerHeight + 24)
    }

    private var playhead: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)

            Capsule()
                .fill(.white)
                .frame(width: 2)
        }
        .padding(.vertical, 2)
        .shadow(color: .black.opacity(0.35), radius: 2)
        .allowsHitTesting(false)
    }

    private var trackView: some View {
        ZStack(alignment: .leading) {
            thumbnailStrip
            outsideTrimShade

            ForEach(segmentStates) { segment in
                segmentOverlay(segment)
            }

            ForEach(interiorSplitPoints, id: \.self) { point in
                splitHandle(for: point)
            }
        }
        .frame(width: trackWidth, height: Constants.trackHeight, alignment: .leading)
        .coordinateSpace(.named(Constants.trackSpace))
    }

    private var thumbnailStrip: some View {
        HStack(spacing: 0) {
            ForEach(video.thumbnailsImages) { thumbnail in
                Group {
                    if let image = thumbnail.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Constants.trackHeight)
                .clipped()
            }
        }
        .frame(width: trackWidth, height: Constants.trackHeight)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var outsideTrimShade: some View {
        let start = x(forSource: video.rangeDuration.lowerBound)
        let end = x(forSource: video.rangeDuration.upperBound)

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(.black.opacity(0.55))
                .frame(width: max(start, 0))

            Rectangle()
                .fill(.black.opacity(0.55))
                .frame(width: max(trackWidth - end, 0))
                .offset(x: end)
        }
        .frame(width: trackWidth, height: Constants.trackHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            actionButton(
                title: VideoEditorStrings.splitAction,
                systemImage: "scissors",
                isEnabled: availability.canSplit,
                isProminent: true,
                action: onSplit
            )
            actionButton(
                title: VideoEditorStrings.splitDeleteAction,
                systemImage: "trash",
                isEnabled: availability.canDelete,
                tint: .red,
                action: onDelete
            )
            actionButton(
                title: VideoEditorStrings.splitRestorePartAction,
                systemImage: "arrow.uturn.backward",
                isEnabled: availability.canRestorePart,
                action: onRestorePart
            )
            actionButton(
                title: VideoEditorStrings.splitJoinAction,
                systemImage: "link",
                isEnabled: availability.canJoin,
                action: onJoin
            )
            actionButton(
                title: VideoEditorStrings.splitRestoreAllAction,
                systemImage: "arrow.counterclockwise",
                isEnabled: availability.hasRemovedSegments,
                action: onRestoreAll
            )
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .animation(.snappy(duration: 0.2), value: availability)
    }

    // MARK: - Initializer

    init(
        currentTime: Double,
        video: Video,
        splitRevision: Int,
        availability: EditorViewModel.SplitActionAvailability,
        onSplit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRestorePart: @escaping () -> Void,
        onRestoreAll: @escaping () -> Void,
        onJoin: @escaping () -> Void,
        onMoveSplit: @escaping (_ point: Double, _ newSourceTime: Double) -> Void,
        onScrubBegan: @escaping () -> Void,
        onScrubChanged: @escaping (_ time: Double) -> Void,
        onScrubEnded: @escaping (_ time: Double) -> Void
    ) {
        self.currentTime = currentTime
        self.video = video
        self.splitRevision = splitRevision
        self.availability = availability
        self.onSplit = onSplit
        self.onDelete = onDelete
        self.onRestorePart = onRestorePart
        self.onRestoreAll = onRestoreAll
        self.onJoin = onJoin
        self.onMoveSplit = onMoveSplit
        self.onScrubBegan = onScrubBegan
        self.onScrubChanged = onScrubChanged
        self.onScrubEnded = onScrubEnded
    }

    // MARK: - Private Methods

    private func ruler() -> some View {
        let step = rulerStep
        let scale = pixelsPerSecond
        let duration = video.timelineDuration

        return Canvas { context, size in
            let halfStep = step / 2
            let count = Int(duration / halfStep) + 1

            for index in 0...count {
                let time = Double(index) * halfStep
                let positionX = CGFloat(time) * scale
                guard positionX <= size.width else { break }

                let isMajor = index % 2 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: positionX, y: size.height))
                tick.addLine(to: CGPoint(x: positionX, y: size.height - (isMajor ? 6 : 3)))
                context.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

                if isMajor {
                    context.draw(
                        Text(Self.format(time))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary),
                        at: CGPoint(x: positionX + 3, y: 6),
                        anchor: .leading
                    )
                }
            }
        }
        .frame(width: trackWidth, height: Constants.rulerHeight)
        .accessibilityHidden(true)
    }

    private func segmentOverlay(_ segment: VideoSplitEditor.SegmentState) -> some View {
        let startX = x(forSource: segment.range.lowerBound)
        let width = max(x(forSource: segment.range.upperBound) - startX, 1)
        let isSelected = segment.range == selectedRange

        return ZStack {
            if segment.isRemoved {
                Rectangle().fill(.black.opacity(0.7))

                if width > 28 {
                    Image(systemName: "trash.slash")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: width, height: Constants.trackHeight)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
        }
        .offset(x: startX)
        .allowsHitTesting(false)
    }

    private func splitHandle(for point: Double) -> some View {
        let previewPoint = previewPoint(for: point)
        let handleHeight = Constants.trackHeight + 8

        return Capsule()
            .fill(.white)
            .frame(width: 4, height: handleHeight)
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.35))
                    .frame(width: 1.5, height: 14)
            }
            .shadow(color: .black.opacity(0.3), radius: 2)
            .frame(width: Constants.handleHitWidth, height: handleHeight)
            .contentShape(Rectangle())
            .offset(x: x(forSource: previewPoint) - Constants.handleHitWidth / 2)
            .highPriorityGesture(dragGesture(for: point))
            .accessibilityLabel(VideoEditorStrings.splitPointAccessibility)
    }

    private func dragGesture(for point: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Constants.trackSpace))
            .onChanged { value in
                draggedSplit = DraggedSplit(
                    point: point,
                    proposedTime: proposedTime(for: point, translation: value.translation.width)
                )
            }
            .onEnded { value in
                let target = resolvedPoint(
                    for: point,
                    proposedTime: proposedTime(for: point, translation: value.translation.width)
                )
                draggedSplit = nil
                onMoveSplit(point, target)
            }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        isProminent: Bool = false,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isProminent && isEnabled ? Color.black : tint)
            .background {
                if isProminent && isEnabled {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                }
            }
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func previewPoint(for point: Double) -> Double {
        guard let draggedSplit, draggedSplit.point == point else { return point }
        return resolvedPoint(for: point, proposedTime: draggedSplit.proposedTime)
    }

    private func proposedTime(for point: Double, translation: CGFloat) -> Double {
        point + Double(translation / pixelsPerSecond) * rate
    }

    private func resolvedPoint(for point: Double, proposedTime: Double) -> Double {
        VideoSplitEditor.movingSplitPoint(
            point,
            to: proposedTime,
            trim: video.rangeDuration,
            splitPoints: video.splitPoints,
            removedRanges: video.removedRanges
        )?.point ?? point
    }

    private func x(forSource sourceTime: Double) -> CGFloat {
        CGFloat(sourceTime / rate) * pixelsPerSecond
    }

    private func time(forOffset offset: CGFloat) -> Double {
        min(max(Double(offset / pixelsPerSecond), 0), video.timelineDuration)
    }

    private func syncScroll(to time: Double) {
        scrollPosition.scrollTo(x: CGFloat(time) * pixelsPerSecond)
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, Constants.minimumPixelsPerSecond), Constants.maximumPixelsPerSecond)
    }

    nonisolated private static func format(_ seconds: Double) -> String {
        let safeSeconds = max(seconds, 0)
        let minutes = Int(safeSeconds) / 60
        let remainder = safeSeconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, remainder)
    }

}