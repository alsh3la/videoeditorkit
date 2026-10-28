//
//  SplitActionBar.swift
//  VideoEditorKit
//

import SwiftUI

/// CapCut / VN style action bar for the split tool: icon over label, Split highlighted,
/// actions that are not valid at the playhead are dimmed.
struct SplitActionBar: View {

    // MARK: - Public Properties

    let canSplit: Bool
    let canDelete: Bool
    let canRestorePart: Bool
    let canJoin: Bool
    let showsRestoreAll: Bool
    let hapticTrigger: Int
    let onSplit: () -> Void
    let onDelete: () -> Void
    let onRestorePart: () -> Void
    let onJoin: () -> Void
    let onRestoreAll: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            actionButton(
                title: VideoEditorStrings.splitAction,
                systemImage: "scissors",
                isEnabled: canSplit,
                isProminent: true,
                action: onSplit
            )

            if canRestorePart {
                actionButton(
                    title: VideoEditorStrings.splitRestorePartAction,
                    systemImage: "arrow.uturn.backward",
                    isEnabled: true,
                    action: onRestorePart
                )
            } else {
                actionButton(
                    title: VideoEditorStrings.splitDeleteAction,
                    systemImage: "trash",
                    isEnabled: canDelete,
                    tint: .red,
                    action: onDelete
                )
            }

            actionButton(
                title: VideoEditorStrings.splitJoinAction,
                systemImage: "link",
                isEnabled: canJoin,
                action: onJoin
            )

            if showsRestoreAll {
                actionButton(
                    title: VideoEditorStrings.splitRestoreAllAction,
                    systemImage: "arrow.counterclockwise",
                    isEnabled: true,
                    action: onRestoreAll
                )
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.snappy(duration: 0.2), value: canRestorePart)
        .animation(.snappy(duration: 0.2), value: showsRestoreAll)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    // MARK: - Private Methods

    private func actionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        isProminent: Bool = false,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isProminent && isEnabled ? Color.black : tint)
            .background {
                if isProminent && isEnabled {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                }
            }
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

}