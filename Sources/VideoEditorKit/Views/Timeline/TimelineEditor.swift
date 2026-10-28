//
//  TimelineEditor.swift
//  Split
//

import CoreMedia
import Foundation
import Observation

// MARK: - Undo

struct EditorSnapshot: Equatable, Sendable {
    var timeline: Timeline
    var selectedClipIDs: Set<UUID>
    var playhead: CMTime
}

/// Snapshot history. `Timeline` is a value type with copy-on-write storage, so snapshots are cheap.
struct UndoHistory<State: Sendable>: Sendable {

    // MARK: - Public Properties

    private(set) var undoStack = [State]()
    private(set) var redoStack = [State]()

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Private Properties

    private let capacity: Int

    // MARK: - Initializer

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    // MARK: - Public Methods

    /// Records the state from before an edit and invalidates redo.
    mutating func record(_ state: State) {
        undoStack.append(state)
        if undoStack.count > capacity { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    mutating func undo(current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}

// MARK: - Editor

struct SplitEvent: Equatable, Sendable {
    let leftClipID: UUID
    let rightClipID: UUID
    let time: CMTime
}

@MainActor
@Observable
final class TimelineEditor {

    // MARK: - Public Properties

    var timeline: Timeline
    var playhead: CMTime = .zero
    var selectedClipIDs = Set<UUID>()

    /// Bumped on every successful split. Use as a haptic / animation trigger.
    private(set) var splitRevision = 0
    private(set) var lastSplit: SplitEvent?

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    /// Exactly one clip selected, and the playhead is far enough from both of its edges.
    var canSplit: Bool {
        guard
            selectedClipIDs.count == 1,
            let id = selectedClipIDs.first,
            let clip = timeline.clip(withID: id)
        else { return false }

        return ClipSplitter.canSplit(
            clip,
            atTimelineTime: playhead,
            frameDuration: timeline.frameDuration,
            policy: policy
        )
    }

    // MARK: - Private Properties

    private var history = UndoHistory<EditorSnapshot>()
    private let policy: SplitPolicy

    private var snapshot: EditorSnapshot {
        EditorSnapshot(
            timeline: timeline,
            selectedClipIDs: selectedClipIDs,
            playhead: playhead
        )
    }

    // MARK: - Initializer

    init(timeline: Timeline = Timeline(), policy: SplitPolicy = .standard) {
        self.timeline = timeline
        self.policy = policy
    }

    // MARK: - Public Methods

    func select(_ clipID: UUID, extending: Bool = false) {
        if extending {
            if selectedClipIDs.contains(clipID) {
                selectedClipIDs.remove(clipID)
            } else {
                selectedClipIDs.insert(clipID)
            }
        } else {
            selectedClipIDs = [clipID]
        }
    }

    func clearSelection() {
        selectedClipIDs = []
    }

    /// Cuts the selected clip at the playhead. The playhead snaps to the cut frame
    /// and the right clip becomes the selection.
    @discardableResult
    func splitAtPlayhead() -> Bool {
        guard canSplit, let clipID = selectedClipIDs.first else { return false }

        let before = snapshot

        do {
            let result = try timeline.splitClip(
                clipID: clipID,
                at: playhead,
                policy: policy
            )

            history.record(before)
            playhead = result.rightClip.timelineStart
            selectedClipIDs = [result.rightClip.id]
            lastSplit = SplitEvent(
                leftClipID: result.leftClip.id,
                rightClipID: result.rightClip.id,
                time: result.rightClip.timelineStart
            )
            splitRevision += 1
            return true
        } catch {
            return false
        }
    }

    func undo() {
        guard let previous = history.undo(current: snapshot) else { return }
        restore(previous)
    }

    func redo() {
        guard let next = history.redo(current: snapshot) else { return }
        restore(next)
    }

    // MARK: - Private Methods

    private func restore(_ snapshot: EditorSnapshot) {
        timeline = snapshot.timeline
        selectedClipIDs = snapshot.selectedClipIDs
        playhead = snapshot.playhead
        lastSplit = nil
    }
}
