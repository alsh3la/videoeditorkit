import Foundation
import Testing

@testable import VideoEditorKit

@Suite("VideoSplitEditorTests", .serialized)
struct VideoSplitEditorTests {

    // MARK: - Public Methods

    @Test
    func segmentsFollowSplitPointsInsideTheTrimRange() {
        let segments = VideoSplitEditor.segments(in: 2...20, splitPoints: [5, 12, 30])

        #expect(segments == [2...5, 5...12, 12...20])
    }

    @Test
    func splittingRejectsPositionsThatCreateTinySegments() {
        #expect(
            VideoSplitEditor.splitting(
                at: 2.05, trim: 2...20, splitPoints: [], removedRanges: []) == nil)
        #expect(
            VideoSplitEditor.splitting(
                at: 10, trim: 2...20, splitPoints: [], removedRanges: []) == [10])
    }

    @Test
    func splittingRejectsPositionsInsideRemovedRanges() {
        #expect(
            VideoSplitEditor.splitting(
                at: 8, trim: 0...20, splitPoints: [5, 12], removedRanges: [5...12]) == nil)
    }

    @Test
    func removingSegmentAddsItsRangeAndKeepsAtLeastOneSegment() {
        let removed = VideoSplitEditor.removingSegment(
            containing: 8, trim: 0...20, splitPoints: [5, 12], removedRanges: [])

        #expect(removed == [5...12])
        #expect(
            VideoSplitEditor.removingSegment(
                containing: 1, trim: 0...20, splitPoints: [5, 12], removedRanges: [5...12, 12...20])
                == nil)
        #expect(
            VideoSplitEditor.removingSegment(
                containing: 1, trim: 0...20, splitPoints: [], removedRanges: []) == nil)
    }

    @Test
    func effectiveRemovedRangesAreClippedAndMerged() {
        let ranges = VideoSplitEditor.effectiveRemovedRanges(
            trim: 4...18, removedRanges: [0...6, 6...8, 15...25])

        #expect(ranges == [4...8, 15...18])
        #expect(
            abs(
                VideoSplitEditor.removedDuration(
                    trim: 4...18, removedRanges: [0...6, 6...8, 15...25]) - 7) < 0.0001)
    }

    @Test
    func skipTargetPointsToTheEndOfTheRemovedRange() {
        #expect(VideoSplitEditor.skipTarget(for: 6, removedRanges: [5...12]) == 12)
        #expect(VideoSplitEditor.skipTarget(for: 12, removedRanges: [5...12]) == nil)
        #expect(VideoSplitEditor.skipTarget(for: 3, removedRanges: [5...12]) == nil)
    }

    @Test
    func removedDurationBeforeCountsOnlyDeletedTimeAheadOfThePoint() {
        let removed = [5.0...12.0, 15.0...18.0]

        #expect(abs(VideoSplitEditor.removedDuration(before: 3, trim: 0...20, removedRanges: removed)) < 0.0001)
        #expect(abs(VideoSplitEditor.removedDuration(before: 8, trim: 0...20, removedRanges: removed) - 3) < 0.0001)
        #expect(abs(VideoSplitEditor.removedDuration(before: 20, trim: 0...20, removedRanges: removed) - 10) < 0.0001)
    }

    @Test
    @MainActor
    func videoTotalDurationExcludesRemovedSegments() {
        var video = Video.mock
        video.rangeDuration = 0...100
        video.split(atSourceTime: 20)
        video.split(atSourceTime: 60)
        video.deleteSegment(atSourceTime: 30)

        #expect(abs(video.totalDuration - 60) < 0.0001)
        #expect(video.isAppliedTool(for: .cut) == true)

        video.resetRangeDuration()
        #expect(video.hasSplitEdits == false)
    }

    @Test
    func configurationRoundTripsSplitState() throws {
        var configuration = VideoEditingConfiguration()
        configuration.split = .init(
            splitPoints: [5, 12],
            removedRanges: [.init(lowerBound: 5, upperBound: 12)]
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(VideoEditingConfiguration.self, from: data)

        #expect(decoded.split == configuration.split)
    }

}
