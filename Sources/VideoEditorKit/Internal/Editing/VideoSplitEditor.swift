//
//  VideoSplitEditor.swift
//  VideoEditorKit
//

import Foundation

/// Pure helpers for the split tool.
///
/// All values are expressed in source-video seconds (not rate-scaled timeline seconds).
/// A video is divided into segments by `splitPoints` inside the current trim range.
/// Deleted segments are stored as `removedRanges` and are skipped by preview and export.
enum VideoSplitEditor {

    // MARK: - Public Properties

    /// Shortest segment a split is allowed to create.
    static let minimumSegmentDuration = 0.2

    // MARK: - Private Properties

    private static let tolerance = 0.001

    // MARK: - Public Methods

    /// Returns the ordered segments produced by `splitPoints` inside `trim`.
    static func segments(
        in trim: ClosedRange<Double>,
        splitPoints: [Double]
    ) -> [ClosedRange<Double>] {
        guard trim.upperBound > trim.lowerBound else { return [] }

        let innerPoints =
            splitPoints
            .filter { $0 > trim.lowerBound + tolerance && $0 < trim.upperBound - tolerance }
            .sorted()
        let boundaries = [trim.lowerBound] + innerPoints + [trim.upperBound]

        return zip(boundaries, boundaries.dropFirst()).compactMap { lower, upper in
            upper - lower > tolerance ? lower...upper : nil
        }
    }

    /// Returns a new list of split points when `sourceTime` is a valid place to split.
    static func splitting(
        at sourceTime: Double,
        trim: ClosedRange<Double>,
        splitPoints: [Double],
        removedRanges: [ClosedRange<Double>]
    ) -> [Double]? {
        guard sourceTime.isFinite else { return nil }
        guard !isRemoved(sourceTime, in: removedRanges) else { return nil }
        guard
            let segment = segments(in: trim, splitPoints: splitPoints)
                .first(where: { sourceTime >= $0.lowerBound && sourceTime < $0.upperBound })
        else { return nil }

        guard
            sourceTime - segment.lowerBound >= minimumSegmentDuration,
            segment.upperBound - sourceTime >= minimumSegmentDuration
        else { return nil }

        return (splitPoints + [sourceTime]).sorted()
    }

    /// Returns the segment that contains `sourceTime`, if any.
    static func segment(
        containing sourceTime: Double,
        in trim: ClosedRange<Double>,
        splitPoints: [Double]
    ) -> ClosedRange<Double>? {
        let allSegments = segments(in: trim, splitPoints: splitPoints)
        let clampedTime = min(max(sourceTime, trim.lowerBound), trim.upperBound)

        return allSegments.first(where: {
            clampedTime >= $0.lowerBound && clampedTime < $0.upperBound
        }) ?? allSegments.last
    }

    /// Returns the removed ranges after deleting the segment under `sourceTime`.
    /// Returns `nil` when the segment is already removed or is the last remaining segment.
    static func removingSegment(
        containing sourceTime: Double,
        trim: ClosedRange<Double>,
        splitPoints: [Double],
        removedRanges: [ClosedRange<Double>]
    ) -> [ClosedRange<Double>]? {
        guard
            let segment = segment(
                containing: sourceTime,
                in: trim,
                splitPoints: splitPoints
            )
        else { return nil }

        let midpoint = (segment.lowerBound + segment.upperBound) / 2
        guard !isRemoved(midpoint, in: removedRanges) else { return nil }

        let keptSegmentCount = segments(in: trim, splitPoints: splitPoints)
            .filter { !isRemoved(($0.lowerBound + $0.upperBound) / 2, in: removedRanges) }
            .count
        guard keptSegmentCount > 1 else { return nil }

        return normalized(removedRanges + [segment])
    }

    /// Result of moving one split point.
    struct SplitPointMove: Equatable {
        /// Split points after the move.
        let splitPoints: [Double]
        /// Removed ranges after their edges followed the moved point.
        let removedRanges: [ClosedRange<Double>]
        /// Where the point ended up after limits were applied.
        let point: Double
    }

    /// Moves `point` to `newTime`, keeping every part at least `minimumSegmentDuration` long.
    /// Deleted parts that touch the point keep touching it. Returns `nil` when `point` is not a split point.
    static func movingSplitPoint(
        _ point: Double,
        to newTime: Double,
        trim: ClosedRange<Double>,
        splitPoints: [Double],
        removedRanges: [ClosedRange<Double>]
    ) -> SplitPointMove? {
        guard newTime.isFinite else { return nil }

        let innerPoints =
            splitPoints
            .filter { $0 > trim.lowerBound + tolerance && $0 < trim.upperBound - tolerance }
            .sorted()

        guard let innerIndex = innerPoints.firstIndex(where: { abs($0 - point) <= tolerance }) else {
            return nil
        }

        let oldPoint = innerPoints[innerIndex]
        let previousBoundary = innerIndex > 0 ? innerPoints[innerIndex - 1] : trim.lowerBound
        let nextBoundary =
            innerIndex + 1 < innerPoints.count ? innerPoints[innerIndex + 1] : trim.upperBound
        let lowerLimit = previousBoundary + minimumSegmentDuration
        let upperLimit = nextBoundary - minimumSegmentDuration

        guard lowerLimit <= upperLimit else { return nil }

        let movedPoint = min(max(newTime, lowerLimit), upperLimit)

        var updatedPoints = splitPoints
        guard let originalIndex = updatedPoints.firstIndex(where: { abs($0 - oldPoint) <= tolerance })
        else { return nil }
        updatedPoints[originalIndex] = movedPoint
        updatedPoints.sort()

        let updatedRanges = removedRanges.compactMap { range -> ClosedRange<Double>? in
            let lower = abs(range.lowerBound - oldPoint) <= tolerance ? movedPoint : range.lowerBound
            let upper = abs(range.upperBound - oldPoint) <= tolerance ? movedPoint : range.upperBound
            return upper - lower > tolerance ? lower...upper : nil
        }

        return SplitPointMove(
            splitPoints: updatedPoints,
            removedRanges: normalized(updatedRanges),
            point: movedPoint
        )
    }

    /// Returns the removed ranges after bringing back only the deleted part under `sourceTime`.
    /// Returns `nil` when that part is not deleted.
    static func restoringSegment(
        containing sourceTime: Double,
        trim: ClosedRange<Double>,
        splitPoints: [Double],
        removedRanges: [ClosedRange<Double>]
    ) -> [ClosedRange<Double>]? {
        guard
            let segment = segment(
                containing: sourceTime,
                in: trim,
                splitPoints: splitPoints
            )
        else { return nil }

        let midpoint = (segment.lowerBound + segment.upperBound) / 2
        guard isRemoved(midpoint, in: removedRanges) else { return nil }

        var remaining = [ClosedRange<Double>]()

        for range in removedRanges {
            let overlapsSegment =
                range.upperBound > segment.lowerBound + tolerance
                && range.lowerBound < segment.upperBound - tolerance

            guard overlapsSegment else {
                remaining.append(range)
                continue
            }

            if segment.lowerBound - range.lowerBound > tolerance {
                remaining.append(range.lowerBound...segment.lowerBound)
            }

            if range.upperBound - segment.upperBound > tolerance {
                remaining.append(segment.upperBound...range.upperBound)
            }
        }

        return normalized(remaining)
    }

    /// Returns split points after joining the part under `sourceTime` with its next part
    /// (or its previous part when it is the last one). Both parts must be kept or both deleted.
    static func joiningSegment(
        containing sourceTime: Double,
        trim: ClosedRange<Double>,
        splitPoints: [Double],
        removedRanges: [ClosedRange<Double>]
    ) -> [Double]? {
        let allSegments = segments(in: trim, splitPoints: splitPoints)

        guard
            allSegments.count > 1,
            let current = segment(containing: sourceTime, in: trim, splitPoints: splitPoints),
            let index = allSegments.firstIndex(of: current)
        else { return nil }

        let pair =
            index + 1 < allSegments.count
            ? (allSegments[index], allSegments[index + 1])
            : (allSegments[index - 1], allSegments[index])

        let isFirstRemoved = isRemoved((pair.0.lowerBound + pair.0.upperBound) / 2, in: removedRanges)
        let isSecondRemoved = isRemoved((pair.1.lowerBound + pair.1.upperBound) / 2, in: removedRanges)
        guard isFirstRemoved == isSecondRemoved else { return nil }

        let boundary = pair.0.upperBound
        guard
            let pointIndex = splitPoints.firstIndex(where: { abs($0 - boundary) <= tolerance })
        else { return nil }

        var updatedPoints = splitPoints
        updatedPoints.remove(at: pointIndex)
        return updatedPoints
    }

    static func isRemoved(
        _ sourceTime: Double,
        in removedRanges: [ClosedRange<Double>]
    ) -> Bool {
        removedRanges.contains {
            sourceTime >= $0.lowerBound - tolerance && sourceTime < $0.upperBound - tolerance
        }
    }

    /// Removed ranges clipped to `trim`, sorted and merged.
    static func effectiveRemovedRanges(
        trim: ClosedRange<Double>,
        removedRanges: [ClosedRange<Double>]
    ) -> [ClosedRange<Double>] {
        let clipped = removedRanges.compactMap { range -> ClosedRange<Double>? in
            let lower = max(range.lowerBound, trim.lowerBound)
            let upper = min(range.upperBound, trim.upperBound)
            return upper - lower > tolerance ? lower...upper : nil
        }

        return normalized(clipped)
    }

    /// Total removed source seconds inside `trim`.
    static func removedDuration(
        trim: ClosedRange<Double>,
        removedRanges: [ClosedRange<Double>]
    ) -> Double {
        effectiveRemovedRanges(trim: trim, removedRanges: removedRanges)
            .reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    /// Removed source seconds inside `trim` that lie before `sourceTime`.
    static func removedDuration(
        before sourceTime: Double,
        trim: ClosedRange<Double>,
        removedRanges: [ClosedRange<Double>]
    ) -> Double {
        effectiveRemovedRanges(trim: trim, removedRanges: removedRanges)
            .reduce(0) { total, range in
                total + max(min(range.upperBound, sourceTime) - range.lowerBound, 0)
            }
    }

    /// Where playback should jump when it enters a removed range, or `nil` when it should not.
    static func skipTarget(
        for sourceTime: Double,
        removedRanges: [ClosedRange<Double>]
    ) -> Double? {
        removedRanges.first(where: {
            sourceTime >= $0.lowerBound - tolerance && sourceTime < $0.upperBound - tolerance
        })?.upperBound
    }

    // MARK: - Private Methods

    private static func normalized(
        _ ranges: [ClosedRange<Double>]
    ) -> [ClosedRange<Double>] {
        var merged = [ClosedRange<Double>]()

        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound + tolerance {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }

        return merged
    }

}
