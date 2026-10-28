//
//  ClipSplitting.swift
//  Split
//
//  Pure, non-destructive split. Only in/out points and metadata change;
//  both results reference the same asset.
//

import CoreMedia
import Foundation

// MARK: - Types

enum SplitError: Error, Equatable {
    case clipNotFound
    case invalidTime
    case invalidSpeed
    /// Time is not strictly inside the clip.
    case outsideClip
    /// Clip is shorter than two minimum parts.
    case clipTooShort
    /// Either half would be shorter than the edge tolerance (or one frame).
    case tooCloseToEdge
}

enum SplitTimeBasis: Sendable {
    /// `time` is absolute timeline time.
    case timeline
    /// `time` is measured from the start of the clip.
    case clip
}

struct SplitPolicy: Sendable {
    var edgeTolerance = CMTime(seconds: 0.05, preferredTimescale: 600)

    static let standard = SplitPolicy()
}

// MARK: - Splitter

enum ClipSplitter {

    struct SplitPoint: Equatable {
        /// Frame-snapped absolute cut time.
        let time: CMTime
        let leftDuration: CMTime
        let rightDuration: CMTime
    }

    // MARK: - Public Methods

    /// Validates and snaps `time`. Cheap enough to call from `body` for enabling the Split button.
    static func splitPoint(
        for clip: Clip,
        atTimelineTime time: CMTime,
        frameDuration: CMTime,
        policy: SplitPolicy = .standard
    ) throws -> SplitPoint {
        guard time.isNumeric else { throw SplitError.invalidTime }

        if clip.playback != .freeze {
            guard clip.speed.isFinite, clip.speed > 0 else { throw SplitError.invalidSpeed }
        }

        guard time > clip.timelineStart, time < clip.timelineEnd else {
            throw SplitError.outsideClip
        }

        let minimumPart = CMTimeMaximum(policy.edgeTolerance, frameDuration)

        guard clip.timelineDuration >= CMTimeMultiply(minimumPart, multiplier: 2) else {
            throw SplitError.clipTooShort
        }

        let cut = snappedToFrame(time, frameDuration: frameDuration)
        let leftDuration = CMTimeSubtract(cut, clip.timelineStart)
        let rightDuration = CMTimeSubtract(clip.timelineEnd, cut)

        guard leftDuration >= minimumPart, rightDuration >= minimumPart else {
            throw SplitError.tooCloseToEdge
        }

        return SplitPoint(time: cut, leftDuration: leftDuration, rightDuration: rightDuration)
    }

    static func canSplit(
        _ clip: Clip,
        atTimelineTime time: CMTime,
        frameDuration: CMTime,
        policy: SplitPolicy = .standard
    ) -> Bool {
        (try? splitPoint(for: clip, atTimelineTime: time, frameDuration: frameDuration, policy: policy))
            != nil
    }

    /// Left keeps the original clip ID. Right is a new instance with new effect IDs.
    static func split(
        _ clip: Clip,
        atTimelineTime time: CMTime,
        frameDuration: CMTime,
        policy: SplitPolicy = .standard
    ) throws -> (left: Clip, right: Clip) {
        let point = try splitPoint(
            for: clip,
            atTimelineTime: time,
            frameDuration: frameDuration,
            policy: policy
        )

        var left = clip
        var right = clip

        right.id = UUID()
        right.effects = clip.effects.map {
            var copy = $0
            copy.id = UUID()
            return copy
        }

        // Timeline side is exact: the two ranges tile the original range with no gap.
        left.timelineRange = CMTimeRange(start: clip.timelineStart, duration: point.leftDuration)
        right.timelineRange = CMTimeRange(start: point.time, duration: point.rightDuration)

        // Source side.
        switch clip.playback {
        case .forward:
            right.sourceStart = advancedSourceTime(of: clip, by: point.leftDuration)
        case .reverse:
            // Timeline order is source-end first, so the left clip owns the upper source part.
            left.sourceStart = advancedSourceTime(of: clip, by: point.rightDuration)
        case .freeze:
            break
        }

        // Edges: in-side properties stay left, out-side properties go right.
        left.transitionIn = clip.transitionIn?.clamped(toMaximum: point.leftDuration)
        left.transitionOut = nil
        right.transitionIn = nil
        right.transitionOut = clip.transitionOut?.clamped(toMaximum: point.rightDuration)

        left.fadeIn = CMTimeMinimum(clip.fadeIn, point.leftDuration)
        left.fadeOut = .zero
        right.fadeIn = .zero
        right.fadeOut = CMTimeMinimum(clip.fadeOut, point.rightDuration)

        // Keyframes are clip-relative.
        var leftChannels = [KeyframeChannel]()
        var rightChannels = [KeyframeChannel]()
        for channel in clip.keyframes {
            let halves = channel.split(at: point.leftDuration)
            leftChannels.append(halves.left)
            rightChannels.append(halves.right)
        }
        left.keyframes = leftChannels
        right.keyframes = rightChannels

        return (left, right)
    }

    static func snappedToFrame(_ time: CMTime, frameDuration: CMTime) -> CMTime {
        guard frameDuration.isNumeric, frameDuration.seconds > 0 else { return time }

        let frames = (time.seconds / frameDuration.seconds).rounded()
        guard frames.isFinite, abs(frames) < Double(Int32.max) else { return time }

        // Exact rational result (e.g. n * 1001/30000), no accumulated float error.
        return CMTimeMultiply(frameDuration, multiplier: Int32(frames))
    }

    // MARK: - Private Methods

    private static func advancedSourceTime(of clip: Clip, by timelineOffset: CMTime) -> CMTime {
        let delta = CMTimeMultiplyByFloat64(timelineOffset, multiplier: clip.speed)
        return CMTimeConvertScale(
            CMTimeAdd(clip.sourceStart, delta),
            timescale: clip.sourceTimescale,
            method: .roundHalfAwayFromZero
        )
    }
}

// MARK: - Timeline API

extension Timeline {

    /// Replaces the clip with two adjacent clips on the same track. Timeline duration is unchanged.
    /// Atomic: throws before mutating.
    @discardableResult
    mutating func splitClip(
        clipID: UUID,
        at time: CMTime,
        basis: SplitTimeBasis = .timeline,
        policy: SplitPolicy = .standard
    ) throws -> (leftClip: Clip, rightClip: Clip) {
        guard let location = location(of: clipID) else { throw SplitError.clipNotFound }

        let clip = tracks[location.track].clips[location.index]
        let absoluteTime =
            switch basis {
            case .timeline: time
            case .clip: CMTimeAdd(clip.timelineStart, time)
            }

        let result = try ClipSplitter.split(
            clip,
            atTimelineTime: absoluteTime,
            frameDuration: frameDuration,
            policy: policy
        )

        tracks[location.track].clips[location.index] = result.left
        tracks[location.track].clips.insert(result.right, at: location.index + 1)

        return (result.left, result.right)
    }
}

/// Free-function form of the requested API.
@discardableResult
func splitClip(
    clipID: UUID,
    at time: CMTime,
    basis: SplitTimeBasis = .timeline,
    in timeline: inout Timeline
) throws -> (leftClip: Clip, rightClip: Clip) {
    try timeline.splitClip(clipID: clipID, at: time, basis: basis)
}
