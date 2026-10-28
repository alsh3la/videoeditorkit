//
//  SplitViews.swift
//  Split
//

import CoreMedia
import SwiftUI

// MARK: - Split Button

struct SplitButton: View {

    // MARK: - Public Properties

    let isEnabled: Bool
    let hapticTrigger: Int
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            Label("Split", systemImage: "scissors")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .disabled(!isEnabled)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }
}

struct SplitToolbar: View {

    // MARK: - Public Properties

    let editor: TimelineEditor

    // MARK: - Body

    var body: some View {
        SplitButton(
            isEnabled: editor.canSplit,
            hapticTrigger: editor.splitRevision
        ) {
            withAnimation(.snappy(duration: 0.25)) {
                editor.splitAtPlayhead()
            }
        }
    }
}

// MARK: - Indicator

/// Thin white line with a scissors badge, drawn over the selected clip at the playhead.
struct SplitIndicatorView: View {

    // MARK: - Public Properties

    /// X position inside the clip, in points.
    let x: CGFloat
    /// Dimmed when a split is not possible at this position.
    let isEnabled: Bool

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.white)
                .frame(width: 1.5)
                .shadow(color: .black.opacity(0.4), radius: 1.5)

            Image(systemName: "scissors")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(.white, in: Circle())
                .offset(y: -9)
        }
        .frame(maxHeight: .infinity)
        .opacity(isEnabled ? 1 : 0.4)
        .offset(x: x - 0.75)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Clip

struct TimelineClipView: View {

    // MARK: - Public Properties

    let clip: Clip
    let isSelected: Bool
    let canSplit: Bool
    let playhead: CMTime
    let pointsPerSecond: CGFloat

    // MARK: - Private Properties

    /// Keeps a clear boundary between adjacent clips. The model itself has no gap.
    private let boundaryGap: CGFloat = 1.5
    private let cornerRadius: CGFloat = 6

    private var width: CGFloat {
        max(clip.timelineDuration.seconds * pointsPerSecond - boundaryGap, 1)
    }

    private var playheadOffsetInClip: CGFloat? {
        let offset = CMTimeSubtract(playhead, clip.timelineStart)
        guard offset > .zero, offset < clip.timelineDuration else { return nil }
        return offset.seconds * pointsPerSecond
    }

    // MARK: - Body

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(clip.kind == .audio ? Color.teal.opacity(0.6) : Color.indigo.opacity(0.6))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelected, let x = playheadOffsetInClip {
                    SplitIndicatorView(x: x, isEnabled: canSplit)
                }
            }
            .frame(width: width)
            .offset(x: clip.timelineStart.seconds * pointsPerSecond)
    }
}

// MARK: - Track

struct TimelineTrackView: View {

    // MARK: - Public Properties

    let track: Track
    let editor: TimelineEditor
    let pointsPerSecond: CGFloat

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.clips) { clip in
                TimelineClipView(
                    clip: clip,
                    isSelected: editor.selectedClipIDs.contains(clip.id),
                    canSplit: editor.canSplit,
                    playhead: editor.playhead,
                    pointsPerSecond: pointsPerSecond
                )
                .onTapGesture {
                    editor.select(clip.id)
                }
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)),
                        removal: .identity
                    )
                )
            }
        }
        .frame(height: 56, alignment: .topLeading)
    }
}
