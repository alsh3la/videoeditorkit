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
            VStack(spacing: 8) {
                splitActionsRow(for: video)

                ThumbnailsSliderView(
                    $bindableVideoPlayer.currentTime,
                    video: $bindableEditorViewModel.currentVideo,
                    isPlaying: videoPlayer.isPlaying,
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
        let canRestore = !video.removedRanges.isEmpty

        return HStack(spacing: 8) {
            Button(action: handleSplitTap) {
                Label(VideoEditorStrings.splitAction, systemImage: "scissors")
            }
            .disabled(!canSplit)

            Button(action: handleDeleteSegmentTap) {
                Label(VideoEditorStrings.splitDeleteAction, systemImage: "trash")
            }
            .disabled(!canDelete)

            Spacer(minLength: 0)

            if canRestore {
                Button(action: handleRestoreSegmentsTap) {
                    Label(
                        VideoEditorStrings.splitRestoreAction,
                        systemImage: "arrow.uturn.backward"
                    )
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 4)
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
        videoPlayer.pause()
        editorViewModel.splitAtPlayhead(timelineTime: videoPlayer.currentTime)
        syncPlayerRemovedRanges()
    }

    private func handleDeleteSegmentTap() {
        videoPlayer.pause()
        editorViewModel.deleteSegmentAtPlayhead(timelineTime: videoPlayer.currentTime)
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

    private func requestThumbnails(_ size: CGSize) {
        editorViewModel.refreshThumbnailsIfNeeded(
            containerSize: size,
            displayScale: displayScale
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
