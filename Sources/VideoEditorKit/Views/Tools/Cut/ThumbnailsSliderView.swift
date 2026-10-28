//
//  ThumbnailsSliderView.swift
//  VideoEditorKit
//
//  Created by Adriano Souza Costa on 23.03.2026.
//

import SwiftUI

struct ThumbnailsSliderView: View {

    // MARK: - Bindings

    @Binding private var currentTime: Double
    @Binding private var video: Video?

    // MARK: - States

    @State private var rangeDuration: ClosedRange<Double> = 0...1
    @State private var isScrubbingPlaybackIndicator = false
    @State private var playbackScrubStartSourceTime: Double?
    @State private var isSynchronizingAnchoredPlayback = false
    @State private var isEditingTrimRange = false
    @State private var zoomLevel: CGFloat = 1
    @State private var viewportWidth: CGFloat = 0
    @State private var scrollOffsetX: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    // MARK: - Private Properties

    private let isPlaying: Bool
    private let splitRevision: Int
    private let isChangeState: Bool?
    private let maximumSelectionDuration: Double?
    private let onPlayPauseTapped: () -> Void
    private let onChangeTimeValue: (ClosedRange<Double>) -> Void
    private let onRequestThumbnails: (CGSize, CGFloat) -> Void
    private let onTrimRangeInteractionStarted: () -> Void
    private let onTrimRangeInteractionEnded: (Double, ClosedRange<Double>) -> Void
    private let onPlaybackScrubStarted: (ClosedRange<Double>) -> Void
    private let onPlaybackScrubChanged: (Double, ClosedRange<Double>) -> Void
    private let onPlaybackScrubEnded: (Double, ClosedRange<Double>) -> Void

    // MARK: - Body

    var body: some View {
        VideoEditorPlaybackTimelineView(
            badgeHeight: playheadLabelHeight,
            trackHeight: timelineHeight
        ) {
            Button {
                onPlayPauseTapped()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: timelineHeight, height: timelineHeight)
                    .circleControl()
            }
        } badge: { size, badgeWidth in
            if let video {
                playheadBadge(
                    size: size,
                    badgeWidth: badgeWidth,
                    video: video
                )
            }
        } track: { size in
            timelineTrack(size)
        } footer: {
            footerSection
        }
        .onChange(of: isChangeState) { _, isChange in
            guard let isChange, !isChange else { return }
            setVideoRange()
        }
        .onChange(of: video?.id) { _, _ in
            setVideoRange()
        }
        .onChange(of: video?.rangeDuration) { _, _ in
            guard !isEditingTrimRange else { return }
            setVideoRange()
        }
        .onChange(of: rangeDuration) { oldRange, newRange in
            syncAnchoredPlaybackIfNeeded(from: oldRange, to: newRange)
        }
        .onChange(of: currentTime) { _, _ in
            guard let video else { return }
            keepPlayheadVisible(in: video)
        }
    }

    // MARK: - Zoom

    private let zoomLevels: [CGFloat] = [1, 2, 4, 8]

    // MARK: - Private Properties

    private let handleInnerInset: CGFloat = 4
    private let playheadLineWidth: CGFloat = 2
    private let playheadLabelHeight: CGFloat = 28
    private let timelineHeight: CGFloat = 60
    private let timelineCornerRadius = RangeSliderMaskedRegionStyle.cornerRadius

    // MARK: - Initializer

    init(
        _ currentTime: Binding<Double>,
        video: Binding<Video?>,
        isPlaying: Bool,
        splitRevision: Int = 0,
        isChangeState: Bool? = nil,
        maximumSelectionDuration: Double? = nil,
        onPlayPauseTapped: @escaping () -> Void,
        onChangeTimeValue: @escaping (ClosedRange<Double>) -> Void,
        onRequestThumbnails: @escaping (CGSize, CGFloat) -> Void,
        onTrimRangeInteractionStarted: @escaping () -> Void,
        onTrimRangeInteractionEnded: @escaping (Double, ClosedRange<Double>) -> Void,
        onPlaybackScrubStarted: @escaping (ClosedRange<Double>) -> Void,
        onPlaybackScrubChanged: @escaping (Double, ClosedRange<Double>) -> Void,
        onPlaybackScrubEnded: @escaping (Double, ClosedRange<Double>) -> Void
    ) {
        _currentTime = currentTime
        _video = video
        _rangeDuration = State(
            initialValue: Self.resolvedVideoRange(
                from: video.wrappedValue
            )
        )

        self.isPlaying = isPlaying
        self.splitRevision = splitRevision
        self.isChangeState = isChangeState
        self.maximumSelectionDuration = maximumSelectionDuration
        self.onPlayPauseTapped = onPlayPauseTapped
        self.onChangeTimeValue = onChangeTimeValue
        self.onRequestThumbnails = onRequestThumbnails
        self.onTrimRangeInteractionStarted = onTrimRangeInteractionStarted
        self.onTrimRangeInteractionEnded = onTrimRangeInteractionEnded
        self.onPlaybackScrubStarted = onPlaybackScrubStarted
        self.onPlaybackScrubChanged = onPlaybackScrubChanged
        self.onPlaybackScrubEnded = onPlaybackScrubEnded
    }

}

extension ThumbnailsSliderView {

    private var footerSection: some View {
        HStack(spacing: 8) {
            if let video {
                let playbackRange = outputRange(for: video, sourceRange: rangeDuration)

                footerTime(playbackRange.lowerBound)
                Spacer()
                zoomControls
                Spacer()
                footerTime(playbackRange.upperBound)
            }
        }
        .padding(.horizontal, 4)
    }

    private var timelineBackground: some View {
        Rectangle()
            .fill(Color(uiColor: .secondarySystemBackground).opacity(0.5))
    }

    // MARK: - Private Methods

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Button {
                changeZoom(by: -1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomLevel <= zoomLevels[0])
            .accessibilityLabel(VideoEditorStrings.timelineZoomOut)

            Text("\(Int(zoomLevel))x")
                .font(.caption2.monospacedDigit().weight(.medium))
                .frame(minWidth: 24)

            Button {
                changeZoom(by: 1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomLevel >= (zoomLevels.last ?? 1))
            .accessibilityLabel(VideoEditorStrings.timelineZoomIn)
        }
        .font(.footnote)
        .foregroundStyle(Theme.primary)
    }

    private func changeZoom(by step: Int) {
        guard let index = zoomLevels.firstIndex(of: zoomLevel) else { return }

        let newIndex = min(max(index + step, 0), zoomLevels.count - 1)
        guard newIndex != index else { return }

        zoomLevel = zoomLevels[newIndex]

        guard zoomLevel > 1 else {
            scrollOffsetX = 0
            return
        }

        guard let video else { return }

        let metrics = timelineMetrics(for: video, width: viewportWidth * zoomLevel)
        let target = metrics.playbackPositionX() - (viewportWidth / 2)

        scrollToContentX(target, animated: false)
        Task { @MainActor in
            scrollToContentX(target, animated: false)
        }
    }

    private func keepPlayheadVisible(in video: Video) {
        guard zoomLevel > 1, viewportWidth > 0 else { return }

        let metrics = timelineMetrics(for: video, width: viewportWidth * zoomLevel)
        let playheadX = metrics.playbackPositionX()
        let margin: CGFloat = 24

        guard
            playheadX < scrollOffsetX + margin
                || playheadX > scrollOffsetX + viewportWidth - margin
        else { return }

        scrollToContentX(
            playheadX - (viewportWidth / 2),
            animated: !isScrubbingPlaybackIndicator
        )
    }

    private func scrollToContentX(_ x: CGFloat, animated: Bool) {
        let maximumOffset = max((viewportWidth * zoomLevel) - viewportWidth, 0)
        let target = min(max(x, 0), maximumOffset)

        if animated {
            withAnimation(.smooth(duration: 0.25)) {
                scrollPosition.scrollTo(x: target)
            }
        } else {
            scrollPosition.scrollTo(x: target)
        }
    }

    private func footerTime(_ value: Double) -> some View {
        Text(value.formatterPreciseTimeString())
            .foregroundStyle(Theme.primary)
            .font(.caption2.weight(.medium))
    }

    private func syncAnchoredPlaybackIfNeeded(
        from oldRange: ClosedRange<Double>,
        to newRange: ClosedRange<Double>
    ) {
        guard let video else { return }
        guard video.rangeDuration != newRange else { return }
        guard oldRange != newRange else { return }

        let previousOutputRange = outputRange(for: video, sourceRange: oldRange)
        let newOutputRange = outputRange(for: video, sourceRange: newRange)

        if currentTime < newOutputRange.lowerBound {
            beginAnchoredPlaybackSynchronizationIfNeeded(previousOutputRange)
            currentTime = newOutputRange.lowerBound
            onPlaybackScrubChanged(newOutputRange.lowerBound, newOutputRange)
            return
        }

        if currentTime > newOutputRange.upperBound {
            beginAnchoredPlaybackSynchronizationIfNeeded(previousOutputRange)
            currentTime = newOutputRange.upperBound
            onPlaybackScrubChanged(newOutputRange.upperBound, newOutputRange)
        }
    }

    private func beginAnchoredPlaybackSynchronizationIfNeeded(_ range: ClosedRange<Double>) {
        guard !isSynchronizingAnchoredPlayback else { return }

        isSynchronizingAnchoredPlayback = true
        onPlaybackScrubStarted(range)
    }

    private func beginTrimRangeInteraction() {
        guard !isEditingTrimRange else { return }

        isEditingTrimRange = true
        onTrimRangeInteractionStarted()
    }

    private func setVideoRange() {
        if let video {
            rangeDuration = Self.resolvedVideoRange(from: video)
        }
    }

    private func commitRangeChange() {
        guard let video else { return }

        self.video?.rangeDuration = rangeDuration

        guard let updatedVideo = self.video else { return }
        let updatedOutputRange = updatedVideo.outputRangeDuration

        if isSynchronizingAnchoredPlayback {
            onPlaybackScrubEnded(currentTime, updatedOutputRange)
            isSynchronizingAnchoredPlayback = false
        }

        guard video.rangeDuration != rangeDuration else {
            finishTrimRangeInteractionIfNeeded(updatedOutputRange)
            return
        }

        onChangeTimeValue(updatedOutputRange)
        finishTrimRangeInteractionIfNeeded(updatedOutputRange)
    }

    private func finishTrimRangeInteractionIfNeeded(_ updatedOutputRange: ClosedRange<Double>) {
        guard isEditingTrimRange else { return }

        isEditingTrimRange = false
        onTrimRangeInteractionEnded(currentTime, updatedOutputRange)
    }

    private func timelineTrack(_ viewportSize: CGSize) -> some View {
        let contentSize = CGSize(
            width: viewportSize.width * zoomLevel,
            height: viewportSize.height
        )

        return Group {
            if zoomLevel > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    trackContent(contentSize)
                        .frame(width: contentSize.width, height: contentSize.height)
                }
                .scrollPosition($scrollPosition)
                .scrollClipDisabled()
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { _, newOffset in
                    scrollOffsetX = newOffset
                }
                .frame(width: viewportSize.width, height: viewportSize.height)
            } else {
                trackContent(contentSize)
            }
        }
        .onAppear {
            setVideoRange()
            viewportWidth = viewportSize.width
        }
        .onChange(of: viewportSize.width) { _, newWidth in
            viewportWidth = newWidth
        }
        .task(id: thumbnailRequestID(for: viewportSize)) {
            onRequestThumbnails(viewportSize, zoomLevel)
        }
    }

    private func trackContent(_ size: CGSize) -> some View {
        ZStack {
            timelineSurface(size)

            if let video {
                RangedSliderView(
                    $rangeDuration,
                    bounds: 0...video.originalDuration,
                    step: 0.001,
                    minimumDistance: EditorPlaybackEditingCoordinator.minimumTrimDuration(
                        for: video.originalDuration
                    ),
                    maximumDistance: maximumSelectionDuration,
                    onStartChange: beginTrimRangeInteraction,
                    onEndChange: commitRangeChange
                )

                splitOverlay(size: size, video: video)

                playbackIndicator(
                    size: size,
                    video: video
                )
                .zIndex(999)
            }
        }
    }

    private static func resolvedVideoRange(
        from video: Video?
    ) -> ClosedRange<Double> {
        guard let video else { return 0...1 }

        let rangeDuration = video.rangeDuration
        let hasValidTrimRange = rangeDuration.upperBound > rangeDuration.lowerBound

        guard max(video.originalDuration, 0) > 0, !hasValidTrimRange else {
            return rangeDuration
        }

        return 0...video.originalDuration
    }

    @ViewBuilder
    private func timelineSurface(_ size: CGSize) -> some View {
        ZStack {
            timelineBackground
            thumbnailsImagesSection(size)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: timelineCornerRadius,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
        .gesture(
            trackScrubGesture(width: size.width),
            including: zoomLevel > 1 ? .subviews : .all
        )
        .onTapGesture { location in
            guard zoomLevel > 1, let video else { return }
            seekPlayhead(toX: location.x, video: video, width: size.width)
        }
    }

    private func seekPlayhead(
        toX x: CGFloat,
        video: Video,
        width: CGFloat
    ) {
        let outputRange = video.outputRangeDuration
        let scrubTime = playheadTime(forX: x, video: video, width: width)

        onPlaybackScrubStarted(outputRange)
        currentTime = scrubTime
        onPlaybackScrubChanged(scrubTime, outputRange)
        onPlaybackScrubEnded(scrubTime, outputRange)
    }

    /// Lets the playhead be dragged (or tapped into place) anywhere on the track, paused or playing.
    /// The trim handles sit above the track, so they keep priority at the edges.
    private func trackScrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard let video else { return }

                let outputRange = video.outputRangeDuration

                if !isScrubbingPlaybackIndicator {
                    isScrubbingPlaybackIndicator = true
                    onPlaybackScrubStarted(outputRange)
                }

                let scrubTime = playheadTime(forX: gesture.location.x, video: video, width: width)
                currentTime = scrubTime
                onPlaybackScrubChanged(scrubTime, outputRange)
            }
            .onEnded { gesture in
                guard let video else {
                    isScrubbingPlaybackIndicator = false
                    return
                }

                let outputRange = video.outputRangeDuration
                let scrubTime = playheadTime(forX: gesture.location.x, video: video, width: width)
                currentTime = scrubTime
                isScrubbingPlaybackIndicator = false
                onPlaybackScrubEnded(scrubTime, outputRange)
            }
    }

    private func playheadTime(
        forX x: CGFloat,
        video: Video,
        width: CGFloat
    ) -> Double {
        let metrics = timelineMetrics(for: video, width: width)

        return PlaybackTimeMapping.timelineTime(
            fromSourceTime: metrics.sourceTime(forX: x),
            rate: video.rate
        )
    }

    @ViewBuilder
    private func thumbnailsImagesSection(_ size: CGSize) -> some View {
        if let video {
            if video.thumbnailsImages.isEmpty {
                ProgressView()
            } else {
                HStack(spacing: 0) {
                    ForEach(video.thumbnailsImages) { trimData in
                        thumbnailCell(
                            trimData,
                            in: size,
                            thumbnailCount: video.thumbnailsImages.count
                        )
                    }
                }
            }
        }
    }

    private func splitOverlay(
        size: CGSize,
        video: Video
    ) -> some View {
        let metrics = timelineMetrics(for: video, width: size.width)
        let removedRanges = VideoSplitEditor.effectiveRemovedRanges(
            trim: rangeDuration,
            removedRanges: video.removedRanges
        )
        let splitPoints = video.splitPoints.filter {
            $0 > rangeDuration.lowerBound && $0 < rangeDuration.upperBound
        }

        let activeSegment =
            splitPoints.isEmpty
            ? nil
            : VideoSplitEditor.segment(
                containing: sourceTime(for: video, timelineTime: currentTime),
                in: rangeDuration,
                splitPoints: video.splitPoints
            )

        return ZStack(alignment: .topLeading) {
            ForEach(Array(removedRanges.enumerated()), id: \.offset) { _, range in
                let startX = metrics.positionX(forSourceTime: range.lowerBound)
                let endX = metrics.positionX(forSourceTime: range.upperBound)
                let width = max(endX - startX, 0)

                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .overlay {
                        if width > 22 {
                            Image(systemName: "trash.slash")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(width: width, height: size.height)
                    .offset(x: startX)
            }

            if let activeSegment {
                let startX = metrics.positionX(forSourceTime: activeSegment.lowerBound)
                let endX = metrics.positionX(forSourceTime: activeSegment.upperBound)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.yellow, lineWidth: 2)
                    .frame(width: max(endX - startX, 0), height: size.height)
                    .offset(x: startX)
            }

            ForEach(Array(splitPoints.enumerated()), id: \.offset) { _, point in
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: size.height)
                    .offset(x: metrics.positionX(forSourceTime: point) - 1)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .id(splitRevision)
        .allowsHitTesting(false)
    }

    private func playbackIndicator(
        size: CGSize,
        video: Video
    ) -> some View {
        let metrics = timelineMetrics(for: video, width: size.width)

        return Capsule(style: .continuous)
            .fill(.blue)
            .frame(width: playheadLineWidth, height: size.height + 10)
            .position(
                x: metrics.playbackPositionX(),
                y: size.height / 2
            )
            .allowsHitTesting(false)
    }

    private func playheadBadge(
        size: CGSize,
        badgeWidth: CGFloat,
        video: Video
    ) -> some View {
        let metrics = timelineMetrics(for: video, width: size.width * zoomLevel)
        let clampedX: CGFloat = {
            guard zoomLevel > 1 else { return metrics.badgePositionX(for: badgeWidth) }

            let halfWidth = max(badgeWidth / 2, 24)
            let visibleX = metrics.playbackPositionX() - scrollOffsetX

            return min(max(visibleX, halfWidth), max(size.width - halfWidth, halfWidth))
        }()
        let playbackRange = video.outputRangeDuration
        let removedBeforePlayhead =
            VideoSplitEditor.removedDuration(
                before: sourceTime(for: video, timelineTime: currentTime),
                trim: video.rangeDuration,
                removedRanges: video.removedRanges
            ) / Double(max(video.rate, 0.001))
        let currentClipTime = max(
            currentTime.clamped(to: playbackRange) - playbackRange.lowerBound - removedBeforePlayhead,
            0
        )
        let clipDuration =
            video.removedRanges.isEmpty
            ? playbackRange.upperBound - playbackRange.lowerBound
            : video.totalDuration

        return Text(
            "\(currentClipTime.formatterPreciseTimeString()) / \(clipDuration.formatterPreciseTimeString())"
        )
        .font(.caption2)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .capsuleControl()
        .position(x: clampedX, y: 12)
        .gesture(
            playbackIndicatorGesture(
                video: video,
                width: size.width * zoomLevel
            )
        )
    }

    private func playbackIndicatorGesture(
        video: Video,
        width: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isScrubbingPlaybackIndicator {
                    isScrubbingPlaybackIndicator = true
                    playbackScrubStartSourceTime = sourceTime(for: video, timelineTime: currentTime)
                    onPlaybackScrubStarted(video.outputRangeDuration)
                }

                let scrubTime = playbackTime(
                    for: gesture.translation.width,
                    startingAt: playbackScrubStartSourceTime ?? sourceTime(for: video, timelineTime: currentTime),
                    video: video,
                    width: width
                )
                currentTime = scrubTime
                onPlaybackScrubChanged(scrubTime, video.outputRangeDuration)
            }
            .onEnded { gesture in
                let scrubTime = playbackTime(
                    for: gesture.translation.width,
                    startingAt: playbackScrubStartSourceTime ?? sourceTime(for: video, timelineTime: currentTime),
                    video: video,
                    width: width
                )
                currentTime = scrubTime
                isScrubbingPlaybackIndicator = false
                playbackScrubStartSourceTime = nil
                onPlaybackScrubEnded(scrubTime, video.outputRangeDuration)
            }
    }

    private func playbackTime(
        for translationWidth: CGFloat,
        startingAt startSourceTime: Double,
        video: Video,
        width: CGFloat
    ) -> Double {
        guard width > 0, video.originalDuration > 0 else {
            return video.outputRangeDuration.lowerBound
        }

        let metrics = timelineMetrics(for: video, width: width)
        let startX = metrics.positionX(forSourceTime: startSourceTime)
        let sourceTime = metrics.sourceTime(forX: startX + translationWidth)

        return PlaybackTimeMapping.timelineTime(fromSourceTime: sourceTime, rate: video.rate)
    }

    private func thumbnailRequestID(for size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let videoID = video?.id.uuidString ?? "none"
        return "\(videoID)-\(width)-\(height)-\(Int(zoomLevel))"
    }

    @ViewBuilder
    private func thumbnailCell(
        _ trimData: ThumbnailImage,
        in size: CGSize,
        thumbnailCount: Int
    ) -> some View {
        let width = size.width / CGFloat(max(thumbnailCount, 1))
        let height = size.height

        Group {
            if let image = trimData.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.tertiary)
            }
        }
        .frame(
            width: width,
            height: height
        )
        .clipped()
    }

    private func timelineMetrics(
        for video: Video,
        width: CGFloat
    ) -> TimelineMetrics {
        TimelineMetrics(
            duration: video.originalDuration,
            playbackRange: rangeDuration,
            currentTime: sourceTime(for: video, timelineTime: currentTime),
            width: width,
            handleInset: handleInnerInset,
            playbackIndicatorWidth: playheadLineWidth
        )
    }

    private func outputRange(
        for video: Video,
        sourceRange: ClosedRange<Double>
    ) -> ClosedRange<Double> {
        PlaybackTimeMapping.scaledTimelineRange(
            sourceRange: sourceRange,
            rate: video.rate,
            originalDuration: video.originalDuration
        )
    }

    private func sourceTime(
        for video: Video,
        timelineTime: Double
    ) -> Double {
        PlaybackTimeMapping.sourceTime(
            forTimelineTime: timelineTime,
            rate: video.rate,
            originalDuration: video.originalDuration
        )
        .clamped(to: rangeDuration)
    }
}

#Preview {
    ThumbnailsSliderView(
        .constant(0),
        video: .constant(Video.mock),
        isPlaying: false,
        isChangeState: nil,
        onPlayPauseTapped: {},
        onChangeTimeValue: { _ in },
        onRequestThumbnails: { _, _ in },
        onTrimRangeInteractionStarted: {},
        onTrimRangeInteractionEnded: { _, _ in },
        onPlaybackScrubStarted: { _ in },
        onPlaybackScrubChanged: { _, _ in },
        onPlaybackScrubEnded: { _, _ in }
    )
}
