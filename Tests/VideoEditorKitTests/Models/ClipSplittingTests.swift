//
//  ClipSplittingTests.swift
//  Split
//

import CoreMedia
import Foundation
import Testing

@testable import VideoEditorKit

// MARK: - Helpers

private let frame = CMTime(value: 1, timescale: 30)

private func sec(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 600)
}

private func makeClip(
    start: Double = 0,
    duration: Double = 10,
    sourceStart: Double = 0,
    speed: Double = 1,
    playback: PlaybackMode = .forward
) -> Clip {
    Clip(
        assetID: UUID(),
        kind: .video,
        timelineRange: CMTimeRange(start: sec(start), duration: sec(duration)),
        sourceStart: sec(sourceStart),
        speed: speed,
        playback: playback
    )
}

private func split(_ clip: Clip, at seconds: Double) throws -> (left: Clip, right: Clip) {
    try ClipSplitter.split(clip, atTimelineTime: sec(seconds), frameDuration: frame)
}

// MARK: - Splitter

struct ClipSplittingTests {

    @Test func forwardSplitTilesTheOriginalRange() throws {
        let clip = makeClip(start: 2, duration: 10, sourceStart: 1)
        let (left, right) = try split(clip, at: 6)

        #expect(left.id == clip.id)
        #expect(right.id != clip.id)
        #expect(left.assetID == right.assetID)
        #expect(left.timelineStart == sec(2))
        #expect(left.timelineEnd == sec(6))
        #expect(right.timelineStart == sec(6))
        #expect(right.timelineEnd == sec(12))
        #expect(left.sourceStart == sec(1))
        #expect(right.sourceStart == sec(5))
    }

    @Test func speedScalesTheSourceOffset() throws {
        let clip = makeClip(sourceStart: 5, speed: 2)
        let (left, right) = try split(clip, at: 4)

        #expect(left.sourceStart == sec(5))
        #expect(right.sourceStart == sec(13))
        #expect(left.speed == 2)
        #expect(right.speed == 2)
    }

    @Test func reverseSwapsWhichHalfOwnsWhichSource() throws {
        // Source window [2, 12] plays backwards.
        let clip = makeClip(sourceStart: 2, playback: .reverse)
        let (left, right) = try split(clip, at: 4)

        #expect(left.sourceStart == sec(8))  // plays source [8, 12] reversed
        #expect(right.sourceStart == sec(2))  // plays source [2, 8] reversed
        #expect(left.playback == .reverse)
        #expect(right.playback == .reverse)
    }

    @Test func freezeFrameKeepsTheHeldFrame() throws {
        let clip = makeClip(sourceStart: 3, playback: .freeze)
        let (left, right) = try split(clip, at: 4)

        #expect(left.sourceStart == sec(3))
        #expect(right.sourceStart == sec(3))
        #expect(left.sourceDuration == .zero)
        #expect(right.timelineDuration == sec(6))
    }

    @Test func cutSnapsToTheFrameGrid() throws {
        let (left, _) = try split(makeClip(), at: 4.01)
        #expect(left.timelineEnd == CMTime(value: 120, timescale: 30))
    }

    @Test func rejectsEdgesAndShortClips() {
        let clip = makeClip()

        #expect(throws: SplitError.outsideClip) { try split(clip, at: 0) }
        #expect(throws: SplitError.outsideClip) { try split(clip, at: 10) }
        #expect(throws: SplitError.tooCloseToEdge) { try split(clip, at: 0.03) }
        #expect(throws: SplitError.tooCloseToEdge) { try split(clip, at: 9.98) }
        #expect(throws: SplitError.clipTooShort) { try split(makeClip(duration: 0.08), at: 0.04) }
    }

    @Test func effectsAreCopiedWithFreshIDs() throws {
        var clip = makeClip()
        clip.effects = [Effect(name: "blur", parameters: ["radius": 4])]
        clip.volume = 0.5
        clip.transform.scale = 1.5

        let (left, right) = try split(clip, at: 4)

        #expect(left.effects[0].id == clip.effects[0].id)
        #expect(right.effects[0].id != clip.effects[0].id)
        #expect(right.effects[0].parameters == ["radius": 4])
        #expect(right.volume == 0.5)
        #expect(right.transform.scale == 1.5)
    }

    @Test func transitionsAndFadesStayOnTheirOuterEdges() throws {
        var clip = makeClip()
        clip.transitionIn = Transition(name: "fade", duration: sec(1))
        clip.transitionOut = Transition(name: "wipe", duration: sec(1))
        clip.fadeIn = sec(0.5)
        clip.fadeOut = sec(0.5)

        let (left, right) = try split(clip, at: 4)

        #expect(left.transitionIn?.name == "fade")
        #expect(left.transitionOut == nil)
        #expect(right.transitionIn == nil)
        #expect(right.transitionOut?.name == "wipe")
        #expect(left.fadeIn == sec(0.5) && left.fadeOut == .zero)
        #expect(right.fadeIn == .zero && right.fadeOut == sec(0.5))
    }

    @Test func keyframesAreContinuousAcrossTheCut() throws {
        var clip = makeClip()
        clip.keyframes = [
            KeyframeChannel(
                property: .opacity,
                keyframes: [
                    Keyframe(time: .zero, value: 0),
                    Keyframe(time: sec(10), value: 1),
                ]
            )
        ]

        let (left, right) = try split(clip, at: 4)
        let leftChannel = left.keyframes[0]
        let rightChannel = right.keyframes[0]

        #expect(abs((leftChannel.value(at: sec(4)) ?? -1) - 0.4) < 1e-9)
        #expect(abs((rightChannel.value(at: .zero) ?? -1) - 0.4) < 1e-9)
        #expect(abs((rightChannel.value(at: sec(6)) ?? -1) - 1.0) < 1e-9)
        #expect(abs((rightChannel.value(at: sec(3)) ?? -1) - 0.7) < 1e-9)
    }

    @Test func clipRelativeTimeBasisMatchesTimelineBasis() throws {
        let clip = makeClip(start: 5)
        var a = Timeline(tracks: [Track(kind: .video, clips: [clip])])
        var b = a

        let byTimeline = try a.splitClip(clipID: clip.id, at: sec(9))
        let byClip = try b.splitClip(clipID: clip.id, at: sec(4), basis: .clip)

        #expect(byTimeline.leftClip.timelineRange == byClip.leftClip.timelineRange)
        #expect(byTimeline.rightClip.timelineRange == byClip.rightClip.timelineRange)
    }
}

// MARK: - Timeline

struct TimelineSplitTests {

    @Test func onlyTheTargetTrackChangesAndDurationIsPreserved() throws {
        let target = makeClip(duration: 10)
        let other = makeClip(duration: 8)
        var timeline = Timeline(tracks: [
            Track(kind: .video, clips: [target]),
            Track(kind: .audio, clips: [other]),
        ])
        let durationBefore = timeline.duration

        let result = try splitClip(clipID: target.id, at: sec(4), in: &timeline)

        #expect(timeline.tracks[0].clips.map(\.id) == [result.leftClip.id, result.rightClip.id])
        #expect(timeline.tracks[1].clips == [other])
        #expect(timeline.duration == durationBefore)
        #expect(timeline.tracks[0].clips[0].timelineEnd == timeline.tracks[0].clips[1].timelineStart)
    }

    @Test func failedSplitDoesNotMutate() {
        let clip = makeClip()
        var timeline = Timeline(tracks: [Track(kind: .video, clips: [clip])])
        let before = timeline

        #expect(throws: SplitError.outsideClip) {
            try splitClip(clipID: clip.id, at: sec(99), in: &timeline)
        }
        #expect(throws: SplitError.clipNotFound) {
            try splitClip(clipID: UUID(), at: sec(4), in: &timeline)
        }
        #expect(timeline == before)
    }
}

// MARK: - Editor

@MainActor
struct TimelineEditorSplitTests {

    private func makeEditor() -> (TimelineEditor, Clip) {
        let clip = makeClip()
        let editor = TimelineEditor(
            timeline: Timeline(tracks: [Track(kind: .video, clips: [clip])])
        )
        return (editor, clip)
    }

    @Test func buttonStateFollowsSelectionAndPlayhead() {
        let (editor, clip) = makeEditor()
        editor.playhead = sec(4)
        #expect(!editor.canSplit)  // nothing selected

        editor.select(clip.id)
        #expect(editor.canSplit)

        editor.playhead = sec(0.02)
        #expect(!editor.canSplit)
        editor.playhead = sec(9.98)
        #expect(!editor.canSplit)
    }

    @Test func multipleSelectionDisablesSplit() {
        let a = makeClip()
        let b = makeClip(start: 10)
        let editor = TimelineEditor(
            timeline: Timeline(tracks: [Track(kind: .video, clips: [a, b])])
        )
        editor.playhead = sec(4)
        editor.select(a.id)
        editor.select(b.id, extending: true)

        #expect(!editor.canSplit)
    }

    @Test func splitSelectsRightClipAndKeepsPlayhead() {
        let (editor, clip) = makeEditor()
        editor.select(clip.id)
        editor.playhead = sec(4)

        #expect(editor.splitAtPlayhead())

        let clips = editor.timeline.tracks[0].clips
        #expect(clips.count == 2)
        #expect(editor.selectedClipIDs == [clips[1].id])
        #expect(editor.playhead == sec(4))
        #expect(editor.splitRevision == 1)
    }

    @Test func undoAndRedoRestoreTimelineSelectionAndPlayhead() {
        let (editor, clip) = makeEditor()
        editor.select(clip.id)
        editor.playhead = sec(4)
        editor.splitAtPlayhead()
        let rightID = editor.selectedClipIDs.first

        editor.undo()
        #expect(editor.timeline.tracks[0].clips == [clip])
        #expect(editor.selectedClipIDs == [clip.id])
        #expect(editor.canRedo)

        editor.redo()
        #expect(editor.timeline.tracks[0].clips.count == 2)
        #expect(editor.selectedClipIDs.first == rightID)
        #expect(!editor.canRedo)
    }

    @Test func newEditClearsRedo() {
        let (editor, clip) = makeEditor()
        editor.select(clip.id)
        editor.playhead = sec(4)
        editor.splitAtPlayhead()
        editor.undo()

        editor.select(clip.id)
        editor.playhead = sec(6)
        editor.splitAtPlayhead()

        #expect(!editor.canRedo)
    }
}
