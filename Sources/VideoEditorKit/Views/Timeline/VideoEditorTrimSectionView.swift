//
//  VideoEditorTrimSectionView.swift
//  VideoEditorKit
//
//  Created by Codex on 09.04.2026.
//

import SwiftUI

@MainActor
struct VideoEditorTrimSectionView: View {

    // MARK: - Environments

    @Environment(\.displayScale) private var displayScale

    // MARK: - Private Properties

    private let editorViewModel: EditorViewModel
    private let videoPlayer: VideoPlayerManager

    // MARK: - Body

    var body: some View {
        @Bindable var bindableEditorViewModel = editorViewModel
        @Bindable var bindableVideoPlayer = videoPlayer

        if let video = editorViewModel.currentVideo {
            let splitRevision = editorViewModel.splitRevision

            VStack(spacing: 8) {
                splitActionsRow(for: video)

                ThumbnailsSliderView(
                    $bindableVideoPlayer.currentTime,
                    video: $bindableEditorViewModel.currentVideo,
                    isPlaying: videoPlayer.isPlaying,
                    splitRevision: splitRevision,
                    isChangeState: video.isAppliedTool(for: .cut),
                    maximumSelectionDuration: editorViewModel.maximumTrimDuration(for: video),
                    onPlayPauseTapped: handlePlayPauseTap,
                    onChangeTimeValue: handleTrimRangeChange,
                    onRequestThumbnails: requestThumbnails,
                    onTrimRangeInteractionStarted: {
                        videoPlayer.beginPlaybackInteraction()
                    },
                    onTrimRangeInteractionEnded: { time, range in
                        videoPlayer.endPlaybackInteraction(
                            resumeAt: time,
                            in: range
                        )
                    },
                    onPlaybackScrubStarted: { range in
                        videoPlayer.beginScrubbing(in: range)
                    },
                    onPlaybackScrubChanged: { time, range in
                        videoPlayer.scrub(
                            to: time,
                            in: range
                        )
                    },
                    onPlaybackScrubEnded: { time, range in
                        videoPlayer.endScrubbing(
                            at: time,
                            in: range
                        )
                    }
                )
            }
        }
    }

    // MARK: - Initializer

    init(
        _ editorViewModel: EditorViewModel,
        videoPlayer: VideoPlayerManager
    ) {
        self.editorViewModel = editorViewModel
        self.videoPlayer = videoPlayer
    }

    // MARK: - Private Methods

    private func splitActionsRow(for video: Video) -> some View {
        let sourceTime = PlaybackTimeMapping.sourceTime(
            forTimelineTime: videoPlayer.currentTime,
            rate: video.rate,
            originalDuration: video.originalDuration
        )
        let canSplit =
            VideoSplitEditor.splitting(
                at: sourceTime,
                trim: video.rangeDuration,
                splitPoints: video.splitPoints,
                removedRanges: video.removedRanges
            ) != nil
        let canDelete =
            VideoSplitEditor.removingSegment(
                containing: sourceTime,
                trim: video.rangeDuration,
                splitPoints: video.splitPoints,
                removedRanges: video.removedRanges
            ) != nil
        let canRestorePart =
            VideoSplitEditor.restoringSegment(
                containing: sourceTime,
                trim: video.rangeDuration,
                splitPoints: video.splitPoints,
                removedRanges: video.removedRanges
            ) != nil
        let canJoin =
            VideoSplitEditor.joiningSegment(
                containing: sourceTime,
                trim: video.rangeDuration,
                splitPoints: video.splitPoints,
                removedRanges: video.removedRanges
            ) != nil
        let hasRemovedParts = !video.removedRanges.isEmpty
        let showsRestoreAll = hasRemovedParts && !(canRestorePart && video.removedRanges.count == 1)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: handleSplitTap) {
                    Label(VideoEditorStrings.splitAction, systemImage: "scissors")
                }
                .disabled(!canSplit)

                if canRestorePart {
                    Button(action: handleRestorePartTap) {
                        Label(
                            VideoEditorStrings.splitRestorePartAction,
                            systemImage: "arrow.uturn.backward"
                        )
                    }
                } else {
                    Button(action: handleDeleteSegmentTap) {
                        Label(VideoEditorStrings.splitDeleteAction, systemImage: "trash")
                    }
                    .disabled(!canDelete)
                }

                Button(action: handleJoinTap) {
                    Label(VideoEditorStrings.splitJoinAction, systemImage: "link")
                }
                .disabled(!canJoin)

                if showsRestoreAll {
                    Button(action: handleRestoreSegmentsTap) {
                        Label(
                            VideoEditorStrings.splitRestoreAllAction,
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func handlePlayPauseTap() {
        guard let video = editorViewModel.currentVideo else { return }
        videoPlayer.action(video)
    }

    private func handleTrimRangeChange(_ newRange: ClosedRange<Double>) {
        videoPlayer.updatePlaybackRange(newRange)
        editorViewModel.setCut()
        syncPlayerRemovedRanges()
    }

    private func handleSplitTap() {
        // Read the playhead before pausing: pausing re-syncs `currentTime` from the player,
        // which can still report the position from before a scrub finished seeking.
        let playheadTime = videoPlayer.currentTime

        videoPlayer.pause()
        editorViewModel.splitAtPlayhead(timelineTime: playheadTime)
        syncPlayerRemovedRanges()
    }

    private func handleDeleteSegmentTap() {
        let playheadTime = videoPlayer.currentTime

        videoPlayer.pause()

        guard
            editorViewModel.deleteSegmentAtPlayhead(timelineTime: playheadTime),
            let video = editorViewModel.currentVideo
        else { return }

        syncPlayerRemovedRanges()
        movePlayheadOutOfRemovedRange(in: video, fromTimelineTime: playheadTime)
    }

    /// After deleting, parks the playhead on the nearest kept frame instead of inside the gap.
    private func movePlayheadOutOfRemovedRange(
        in video: Video,
        fromTimelineTime timelineTime: Double
    ) {
        let sourceTime = PlaybackTimeMapping.sourceTime(
            forTimelineTime: timelineTime,
            rate: video.rate,
            originalDuration: video.originalDuration
        )
        let removedRanges = VideoSplitEditor.effectiveRemovedRanges(
            trim: video.rangeDuration,
            removedRanges: video.removedRanges
        )
        guard
            let gap = removedRanges.first(where: { $0.contains(sourceTime) })
        else { return }

        let targetSourceTime =
            gap.upperBound < video.rangeDuration.upperBound - 0.001
            ? gap.upperBound
            : max(gap.lowerBound - 0.05, video.rangeDuration.lowerBound)
        let targetTime = PlaybackTimeMapping.timelineTime(
            fromSourceTime: targetSourceTime,
            rate: video.rate
        )
        let range = video.outputRangeDuration

        videoPlayer.beginScrubbing(in: range)
        videoPlayer.scrub(to: targetTime, in: range)
        videoPlayer.endScrubbing(at: targetTime, in: range)
    }

    private func handleRestorePartTap() {
        let playheadTime = videoPlayer.currentTime

        videoPlayer.pause()
        editorViewModel.restoreSegmentAtPlayhead(timelineTime: playheadTime)
        syncPlayerRemovedRanges()
    }

    private func handleJoinTap() {
        let playheadTime = videoPlayer.currentTime

        videoPlayer.pause()
        editorViewModel.joinSegmentAtPlayhead(timelineTime: playheadTime)
        syncPlayerRemovedRanges()
    }

    private func handleRestoreSegmentsTap() {
        videoPlayer.pause()
        editorViewModel.restoreRemovedSegments()
        syncPlayerRemovedRanges()
    }

    private func syncPlayerRemovedRanges() {
        guard let video = editorViewModel.currentVideo else { return }
        videoPlayer.updateRemovedRanges(from: video)
    }

    private func requestThumbnails(_ size: CGSize, _ zoomLevel: CGFloat) {
        editorViewModel.refreshThumbnailsIfNeeded(
            containerSize: size,
            displayScale: displayScale,
            thumbnailWidthScale: zoomLevel
        )
    }

}

#Preview {
    VideoEditorTrimSectionView(
        EditorViewModel(),
        videoPlayer: VideoPlayerManager()
    )
    .padding()
}
