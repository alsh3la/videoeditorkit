//
//  TimelineModel.swift
//  Split
//
//  Value-type multi-track timeline. Clips reference media by `assetID` and only
//  store in/out points, so every edit is non-destructive.
//

import CoreMedia
import Foundation

// MARK: - Enums

enum TrackKind: String, Codable, Sendable {
    case video
    case overlay
    case audio
}

enum PlaybackMode: Equatable, Sendable {
    case forward
    /// Plays the source window backwards.
    case reverse
    /// Holds the single source frame at `Clip.sourceStart`.
    case freeze
}

// MARK: - Clip Properties

struct ClipTransform: Equatable, Sendable {
    var x = 0.0
    var y = 0.0
    var scale = 1.0
    var rotation = 0.0
    var opacity = 1.0
    var isMirrored = false
}

struct Effect: Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var parameters = [String: Double]()
}

struct Transition: Equatable, Sendable {
    var name: String
    var duration: CMTime

    func clamped(toMaximum limit: CMTime) -> Transition {
        var copy = self
        copy.duration = CMTimeMinimum(duration, limit)
        return copy
    }
}

enum KeyframeProperty: String, Sendable {
    case x, y, scale, rotation, opacity, volume
}

enum KeyframeInterpolation: Equatable, Sendable {
    case linear
    case hold
}

struct Keyframe: Equatable, Sendable {
    /// Clip-relative timeline time (not source time), so speed changes do not affect it.
    var time: CMTime
    var value: Double
    var interpolation: KeyframeInterpolation = .linear
}

struct KeyframeChannel: Equatable, Sendable {

    // MARK: - Public Properties

    var property: KeyframeProperty
    /// Sorted by `time`.
    var keyframes: [Keyframe]

    // MARK: - Public Methods

    func value(at time: CMTime) -> Double? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        guard
            let index = keyframes.lastIndex(where: { $0.time <= time }),
            index + 1 < keyframes.count
        else { return last.value }

        let a = keyframes[index]
        let b = keyframes[index + 1]

        switch a.interpolation {
        case .hold:
            return a.value
        case .linear:
            let span = CMTimeSubtract(b.time, a.time).seconds
            guard span > 0 else { return b.value }
            let fraction = CMTimeSubtract(time, a.time).seconds / span
            return a.value + (b.value - a.value) * fraction
        }
    }

    /// Splits at a clip-relative time. Both halves get a keyframe at the cut that carries the
    /// value the original curve had there, so nothing jumps across the boundary.
    /// Exact for `.linear` and `.hold`. Eased curves would need bezier subdivision.
    func split(at cut: CMTime) -> (left: KeyframeChannel, right: KeyframeChannel) {
        guard let cutValue = value(at: cut) else { return (self, self) }

        let exact = keyframes.first { $0.time == cut }
        let previous = keyframes.last { $0.time < cut }
        let rightInterpolation = exact?.interpolation ?? previous?.interpolation ?? .linear

        var leftKeyframes = keyframes.filter { $0.time < cut }
        leftKeyframes.append(Keyframe(time: cut, value: cutValue))

        var rightKeyframes = [
            Keyframe(time: .zero, value: cutValue, interpolation: rightInterpolation)
        ]
        rightKeyframes += keyframes.filter { $0.time > cut }.map {
            var shifted = $0
            shifted.time = CMTimeSubtract($0.time, cut)
            return shifted
        }

        return (
            KeyframeChannel(property: property, keyframes: leftKeyframes),
            KeyframeChannel(property: property, keyframes: rightKeyframes)
        )
    }
}

// MARK: - Clip

struct Clip: Identifiable, Equatable, Sendable {

    // MARK: - Public Properties

    var id: UUID
    var assetID: UUID
    var kind: TrackKind

    /// Where the clip sits on its track.
    var timelineRange: CMTimeRange
    /// In-point in the source media. For `.reverse` it is the lower end of the source window.
    var sourceStart: CMTime
    /// Preferred timescale of the source track. Source times are rounded to it.
    var sourceTimescale: CMTimeScale
    /// Constant speed multiplier (> 0). Ignored for `.freeze`.
    var speed: Double
    var playback: PlaybackMode

    var volume = 1.0
    var transform = ClipTransform()
    var effects = [Effect]()
    var keyframes = [KeyframeChannel]()
    var transitionIn: Transition?
    var transitionOut: Transition?
    var fadeIn = CMTime.zero
    var fadeOut = CMTime.zero

    var timelineStart: CMTime { timelineRange.start }
    var timelineEnd: CMTime { timelineRange.end }
    var timelineDuration: CMTime { timelineRange.duration }

    /// Length of the source window this clip plays.
    var sourceDuration: CMTime {
        playback == .freeze
            ? .zero
            : CMTimeMultiplyByFloat64(timelineDuration, multiplier: speed)
    }

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        assetID: UUID,
        kind: TrackKind,
        timelineRange: CMTimeRange,
        sourceStart: CMTime = .zero,
        sourceTimescale: CMTimeScale = 600,
        speed: Double = 1,
        playback: PlaybackMode = .forward
    ) {
        self.id = id
        self.assetID = assetID
        self.kind = kind
        self.timelineRange = timelineRange
        self.sourceStart = sourceStart
        self.sourceTimescale = sourceTimescale
        self.speed = speed
        self.playback = playback
    }
}

// MARK: - Track / Timeline

struct Track: Identifiable, Equatable, Sendable {

    // MARK: - Public Properties

    var id = UUID()
    var kind: TrackKind
    /// Ordered by `timelineStart`.
    var clips: [Clip]

    // MARK: - Initializer

    init(id: UUID = UUID(), kind: TrackKind, clips: [Clip] = []) {
        self.id = id
        self.kind = kind
        self.clips = clips
    }
}

struct Timeline: Equatable, Sendable {

    // MARK: - Public Properties

    var tracks: [Track]
    /// Edit-grid frame duration, e.g. `CMTime(value: 1, timescale: 30)` or `1001/30000`.
    var frameDuration: CMTime

    var duration: CMTime {
        tracks.flatMap(\.clips).reduce(CMTime.zero) { CMTimeMaximum($0, $1.timelineEnd) }
    }

    // MARK: - Initializer

    init(
        tracks: [Track] = [],
        frameDuration: CMTime = CMTime(value: 1, timescale: 30)
    ) {
        self.tracks = tracks
        self.frameDuration = frameDuration
    }

    // MARK: - Public Methods

    func location(of clipID: UUID) -> (track: Int, index: Int)? {
        for (trackIndex, track) in tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipID }) {
                return (trackIndex, index)
            }
        }
        return nil
    }

    func clip(withID clipID: UUID) -> Clip? {
        guard let location = location(of: clipID) else { return nil }
        return tracks[location.track].clips[location.index]
    }
}
