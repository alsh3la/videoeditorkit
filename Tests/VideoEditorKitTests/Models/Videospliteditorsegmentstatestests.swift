import Testing

@testable import VideoEditorKit

struct VideoSplitEditorSegmentStatesTests {

    // MARK: - Public Methods

    @Test
    func returnsSingleKeptSegmentWithoutSplits() {
        let states = VideoSplitEditor.segmentStates(
            in: 0...10,
            splitPoints: [],
            removedRanges: []
        )

        #expect(states.count == 1)
        #expect(states.first?.isRemoved == false)
    }

    @Test
    func marksDeletedSegments() {
        let states = VideoSplitEditor.segmentStates(
            in: 0...10,
            splitPoints: [4],
            removedRanges: [4...10]
        )

        #expect(states.map(\.isRemoved) == [false, true])
        #expect(states.map(\.index) == [0, 1])
    }

    @Test
    func ignoresSplitPointsOutsideTrim() {
        let states = VideoSplitEditor.segmentStates(
            in: 2...8,
            splitPoints: [1, 5, 9],
            removedRanges: []
        )

        #expect(states.count == 2)
    }

}
