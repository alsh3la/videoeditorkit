//
//  SplitToolView.swift
//  VideoEditorKit
//

import SwiftUI

/// Hosts `SplitTimelineView` and connects it to the editor view model and the player.
@MainActor
struct SplitToolView: View {

    // MARK: - Private Properties

    private let editorViewModel: EditorViewModel
    private let videoPlayer: VideoPlayerManager

    // MARK: - Body

    var body: some View {
        if let video = editorViewModel.currentVideo {
            let range = video.outputRangeDuration

            SplitTimelineView(
                currentTime: videoPlayer.currentTime,
                video: video,
                splitRevision: editorViewModel.splitRevision,
                availability: editorViewModel.splitActionAvailability(
                    timelineTime: videoPlayer.currentTime
                ),
                onSplit: {
                    perform { editorViewModel.splitAtPlayhead(timelineTime: $0) }
                },
                onDelete: {
                    perform { editorViewModel.deleteSegmentAtPlayhead(timelineTime: $0) }
                },
                onRestorePart: {
                    perform { editorViewModel.restoreSegmentAtPlayhead(timelineTime: $0) }
                },
                onRestoreAll: {
                    videoPlayer.pause()
                    editorViewModel.restoreRemovedSegments()
                },
                onJoin: {
                    perform { editorViewModel.joinSegmentAtPlayhead(timelineTime: $0) }
                },
                onMoveSplit: { point, newTime in
                    videoPlayer.pause()
                    editorViewModel.moveSplitPoint(from: point, to: newTime)
                },
                onScrubBegan: {
                    videoPlayer.beginScrubbing(in: range)
                },
                onScrubChanged: { time in
                    videoPlayer.scrub(to: time, in: range)
                },
                onScrubEnded: { time in
                    videoPlayer.endScrubbing(at: time, in: range)
                }
            )
            .onChange(of: editorViewModel.splitRevision) { _, _ in
                // `Video` compares equal by id, so edits to split points do not trigger
                // the usual current-video observers. Push the new ranges to the player.
                guard let updatedVideo = editorViewModel.currentVideo else { return }
                videoPlayer.syncPlaybackState(with: updatedVideo)
            }
        }
    }

    // MARK: - Initializer

    init(
        editorViewModel: EditorViewModel,
        videoPlayer: VideoPlayerManager
    ) {
        self.editorViewModel = editorViewModel
        self.videoPlayer = videoPlayer
    }

    // MARK: - Private Methods

    private func perform(_ action: (Double) -> Bool) {
        videoPlayer.pause()
        _ = action(videoPlayer.currentTime)
    }

}